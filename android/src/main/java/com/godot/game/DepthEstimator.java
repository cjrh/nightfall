package com.godot.game;

import android.content.Context;
import android.content.res.AssetFileDescriptor;
import android.util.Log;

import org.tensorflow.lite.Interpreter;

import java.io.FileInputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.nio.MappedByteBuffer;
import java.nio.channels.FileChannel;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

public class DepthEstimator {
    private static final String TAG = "DepthEstimator";
    private static final int MIDAS_SIZE = 256;
    private static final int DEPTH_SIZE = 512;
    private static final String MODEL_MIDAS = "midas-midas-v2-w8a8.tflite";
    private static final String MODEL_DEPTH_ANYTHING = "depth-anything-v2-small.tflite";

    private Interpreter tfliteMidas;
    private Interpreter tfliteDepthAnything;
    private Interpreter activeInterpreter;
    private ByteBuffer inputBufferMidas;
    private ByteBuffer inputBufferDA;
    private ByteBuffer outputBufferMidas;
    private ByteBuffer outputBufferDA;
    private int daInputSize = 518;
    private volatile boolean initialized = false;
    private volatile int activeModelIndex = 0;

    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final AtomicBoolean isInferencing = new AtomicBoolean(false);
    private final AtomicReference<byte[]> latestDepthMap = new AtomicReference<>();

    private float[] smoothedDepthFloat = null;

    private float emaMin = 0.0f;
    private float emaMax = 1.0f;
    private boolean emaInitialized = false;
    private static final float EMA_DECAY = 0.9f;

    private Context appContext;

    public synchronized boolean initialize(Context context) {
        if (initialized) return true;
        appContext = context.getApplicationContext();

        try {
            inputBufferMidas = ByteBuffer.allocateDirect(1 * MIDAS_SIZE * MIDAS_SIZE * 3 * 4)
                    .order(ByteOrder.nativeOrder());
            outputBufferMidas = ByteBuffer.allocateDirect(1 * MIDAS_SIZE * MIDAS_SIZE * 1 * 4)
                    .order(ByteOrder.nativeOrder());

            tfliteMidas = loadInterpreter(MODEL_MIDAS);

            try {
                tfliteDepthAnything = loadInterpreter(MODEL_DEPTH_ANYTHING);
                int[] daShape = tfliteDepthAnything.getInputTensor(0).shape();
                daInputSize = daShape[1];
                Log.i(TAG, "Depth Anything V2 model loaded, input size: " + daInputSize + "x" + daInputSize);
                inputBufferDA = ByteBuffer.allocateDirect(1 * daInputSize * daInputSize * 3 * 4)
                        .order(ByteOrder.nativeOrder());
                outputBufferDA = ByteBuffer.allocateDirect(1 * daInputSize * daInputSize * 1 * 4)
                        .order(ByteOrder.nativeOrder());
            } catch (Exception e) {
                Log.w(TAG, "Depth Anything V2 model not available", e);
                tfliteDepthAnything = null;
            }

            activeInterpreter = tfliteMidas;
            activeModelIndex = 0;
            initialized = true;
            Log.i(TAG, "Initialized successfully (MiDaS=" + (tfliteMidas != null) + ", DA=" + (tfliteDepthAnything != null) + ")");
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Failed to initialize", e);
            return false;
        }
    }

    private Interpreter loadInterpreter(String modelFile) throws IOException {
        MappedByteBuffer buffer = loadModelFile(modelFile);
        try {
            Interpreter.Options opts = new Interpreter.Options();
            opts.setUseNNAPI(true);
            opts.setNumThreads(4);
            Interpreter interp = new Interpreter(buffer, opts);
            Log.i(TAG, modelFile + " loaded with NNAPI");
            return interp;
        } catch (Exception e) {
            Log.w(TAG, "NNAPI failed for " + modelFile + ", falling back to CPU", e);
            Interpreter.Options opts = new Interpreter.Options();
            opts.setNumThreads(4);
            return new Interpreter(buffer, opts);
        }
    }

    public void setActiveModel(int modelIndex) {
        if (!initialized) return;
        Interpreter target;
        if (modelIndex == 1 && tfliteDepthAnything != null) {
            target = tfliteDepthAnything;
        } else {
            target = tfliteMidas;
            modelIndex = 0;
        }
        if (activeModelIndex != modelIndex) {
            while (isInferencing.get()) {
                Thread.yield();
            }
            smoothedDepthFloat = null;
            emaInitialized = false;
            activeInterpreter = target;
            activeModelIndex = modelIndex;
            Log.i(TAG, "Switched to model " + (modelIndex == 0 ? "MiDaS" : "Depth Anything V2"));
        }
    }

    public int getActiveModel() {
        return activeModelIndex;
    }

    public void submitFrame(byte[] rgbaPixels, int width, int height) {
        if (!initialized || activeInterpreter == null) return;
        if (rgbaPixels == null || rgbaPixels.length < width * height * 4) return;
        if (!isInferencing.compareAndSet(false, true)) return;

        final byte[] frameCopy = rgbaPixels.clone();
        final int modelIdx = activeModelIndex;
        executor.submit(() -> {
            long startTime = System.nanoTime();
            try {
                byte[] result;
                if (modelIdx == 1) {
                    result = runInferenceDA(frameCopy, width, height);
                } else {
                    result = runInferenceMidas(frameCopy, width, height);
                }
                if (result != null) {
                    latestDepthMap.set(result);
                }
            } catch (Exception e) {
                Log.e(TAG, "Async inference failed", e);
            } finally {
                isInferencing.set(false);
                long duration = (System.nanoTime() - startTime) / 1_000_000;
                Log.d(TAG, "Inference: " + duration + "ms (" + (modelIdx == 1 ? "DA" : "MiDaS") + ")");
            }
        });
    }

    public byte[] getLatestDepth() {
        return latestDepthMap.getAndSet(null);
    }

    private byte[] runInferenceMidas(byte[] rgbaPixels, int width, int height) {
        inputBufferMidas.rewind();
        outputBufferMidas.rewind();

        int srcRowBytes = width * 4;
        float scaleX = (float) width / MIDAS_SIZE;
        float scaleY = (float) height / MIDAS_SIZE;

        for (int y = 0; y < MIDAS_SIZE; y++) {
            int srcY = Math.min((int) (y * scaleY), height - 1);
            int srcRowOff = srcY * srcRowBytes;
            for (int x = 0; x < MIDAS_SIZE; x++) {
                int srcX = Math.min((int) (x * scaleX), width - 1);
                int srcIdx = srcRowOff + srcX * 4;
                inputBufferMidas.putFloat((rgbaPixels[srcIdx] & 0xFF) / 255.0f);
                inputBufferMidas.putFloat((rgbaPixels[srcIdx + 1] & 0xFF) / 255.0f);
                inputBufferMidas.putFloat((rgbaPixels[srcIdx + 2] & 0xFF) / 255.0f);
            }
        }
        inputBufferMidas.rewind();

        tfliteMidas.run(inputBufferMidas, outputBufferMidas);
        outputBufferMidas.rewind();

        return postProcess(outputBufferMidas, MIDAS_SIZE);
    }

    private byte[] runInferenceDA(byte[] rgbaPixels, int width, int height) {
        inputBufferDA.rewind();
        outputBufferDA.rewind();

        int srcRowBytes = width * 4;
        float scaleX = (float) width / daInputSize;
        float scaleY = (float) height / daInputSize;

        for (int y = 0; y < daInputSize; y++) {
            int srcY = Math.min((int) (y * scaleY), height - 1);
            int srcRowOff = srcY * srcRowBytes;
            for (int x = 0; x < daInputSize; x++) {
                int srcX = Math.min((int) (x * scaleX), width - 1);
                int srcIdx = srcRowOff + srcX * 4;
                inputBufferDA.putFloat((rgbaPixels[srcIdx] & 0xFF) / 255.0f);
                inputBufferDA.putFloat((rgbaPixels[srcIdx + 1] & 0xFF) / 255.0f);
                inputBufferDA.putFloat((rgbaPixels[srcIdx + 2] & 0xFF) / 255.0f);
            }
        }
        inputBufferDA.rewind();

        tfliteDepthAnything.run(inputBufferDA, outputBufferDA);
        outputBufferDA.rewind();

        return postProcess(outputBufferDA, daInputSize);
    }

    private byte[] postProcess(ByteBuffer output, int size) {
        output.rewind();
        FloatBuffer floatOut = output.asFloatBuffer();
        float min = Float.MAX_VALUE, max = Float.MIN_VALUE;
        for (int i = 0; i < floatOut.capacity(); i++) {
            float v = floatOut.get(i);
            if (v < min) min = v;
            if (v > max) max = v;
        }

        float range = max - min;
        float[] rawDepth = new float[size * size];
        if (range > 0) {
            floatOut.rewind();
            for (int i = 0; i < floatOut.capacity(); i++) {
                rawDepth[i] = (floatOut.get() - min) / range;
            }
        }

        for (int i = 0; i < rawDepth.length; i++) {
            rawDepth[i] = softplus01(rawDepth[i], 0.687f);
        }

        float[] atDepthSize;
        if (size == DEPTH_SIZE) {
            atDepthSize = rawDepth;
        } else if (size < DEPTH_SIZE) {
            atDepthSize = bilinearUpscale(rawDepth, size, DEPTH_SIZE);
        } else {
            atDepthSize = bilinearDownscale(rawDepth, size, DEPTH_SIZE);
        }

        float[] filtered = separableBilateral(atDepthSize, DEPTH_SIZE, 4, 0.15f);
        float[] filled = edgeAwareDilate(filtered, DEPTH_SIZE);
        float[] smoothed = emaNormalize(filled, DEPTH_SIZE);

        byte[] depthBytes = new byte[DEPTH_SIZE * DEPTH_SIZE];
        float sMin = Float.MAX_VALUE, sMax = Float.MIN_VALUE;
        for (int i = 0; i < smoothed.length; i++) {
            if (smoothed[i] < sMin) sMin = smoothed[i];
            if (smoothed[i] > sMax) sMax = smoothed[i];
        }
        float sRange = sMax - sMin;
        if (sRange > 0) {
            for (int i = 0; i < smoothed.length; i++) {
                float normalized = (smoothed[i] - sMin) / sRange;
                depthBytes[i] = (byte) (normalized * 255.0f);
            }
        }

        applyUiMask(depthBytes);

        return depthBytes;
    }

    private float softplus01(float x, float bias) {
        float k = 8.0f;
        float v = (float) Math.log(1.0 + Math.exp(k * (x - bias))) / k + bias;
        return Math.max(0.0f, Math.min(1.0f, v));
    }

    private float[] bilinearUpscale(float[] input, int inSize, int outSize) {
        float[] output = new float[outSize * outSize];
        float ratio = (float) (inSize - 1) / (outSize - 1);
        for (int y = 0; y < outSize; y++) {
            float srcY = y * ratio;
            int y0 = (int) srcY;
            int y1 = Math.min(y0 + 1, inSize - 1);
            float fy = srcY - y0;
            for (int x = 0; x < outSize; x++) {
                float srcX = x * ratio;
                int x0 = (int) srcX;
                int x1 = Math.min(x0 + 1, inSize - 1);
                float fx = srcX - x0;
                float v00 = input[y0 * inSize + x0];
                float v10 = input[y0 * inSize + x1];
                float v01 = input[y1 * inSize + x0];
                float v11 = input[y1 * inSize + x1];
                float top = v00 * (1 - fx) + v10 * fx;
                float bot = v01 * (1 - fx) + v11 * fx;
                output[y * outSize + x] = top * (1 - fy) + bot * fy;
            }
        }
        return output;
    }

    private float[] separableBilateral(float[] depth, int size, int radius, float sigmaR) {
        float sigmaS = radius * 0.5f;
        float[] spatial = new float[radius * 2 + 1];
        float spatialSum = 0.0f;
        for (int i = -radius; i <= radius; i++) {
            float w = (float) Math.exp(-(i * i) / (2.0f * sigmaS * sigmaS));
            spatial[i + radius] = w;
            spatialSum += w;
        }
        for (int i = 0; i < spatial.length; i++) spatial[i] /= spatialSum;

        float[] horizontal = new float[depth.length];
        for (int y = 0; y < size; y++) {
            for (int x = 0; x < size; x++) {
                float centerVal = depth[y * size + x];
                float wSum = 0.0f;
                float vSum = 0.0f;
                for (int k = -radius; k <= radius; k++) {
                    int nx = Math.min(Math.max(x + k, 0), size - 1);
                    float nv = depth[y * size + nx];
                    float diff = nv - centerVal;
                    float rangeW = (float) Math.exp(-(diff * diff) / (2.0f * sigmaR * sigmaR));
                    float w = spatial[k + radius] * rangeW;
                    wSum += w;
                    vSum += nv * w;
                }
                horizontal[y * size + x] = vSum / wSum;
            }
        }

        float[] result = new float[depth.length];
        for (int x = 0; x < size; x++) {
            for (int y = 0; y < size; y++) {
                float centerVal = horizontal[y * size + x];
                float wSum = 0.0f;
                float vSum = 0.0f;
                for (int k = -radius; k <= radius; k++) {
                    int ny = Math.min(Math.max(y + k, 0), size - 1);
                    float nv = horizontal[ny * size + x];
                    float diff = nv - centerVal;
                    float rangeW = (float) Math.exp(-(diff * diff) / (2.0f * sigmaR * sigmaR));
                    float w = spatial[k + radius] * rangeW;
                    wSum += w;
                    vSum += nv * w;
                }
                result[y * size + x] = vSum / wSum;
            }
        }
        return result;
    }

    private float[] edgeAwareDilate(float[] depth, int size) {
        float[] edgeWeight = new float[size * size];
        for (int y = 0; y < size; y++) {
            for (int x = 0; x < size; x++) {
                float v = depth[y * size + x];
                float vMin = v, vMax = v;
                for (int dy = -1; dy <= 1; dy++) {
                    for (int dx = -1; dx <= 1; dx++) {
                        int ny = Math.min(Math.max(y + dy, 0), size - 1);
                        int nx = Math.min(Math.max(x + dx, 0), size - 1);
                        float nv = depth[ny * size + nx];
                        if (nv < vMin) vMin = nv;
                        if (nv > vMax) vMax = nv;
                    }
                }
                float range = vMax - vMin;
                edgeWeight[y * size + x] = Math.min(range * 8.0f, 1.0f);
            }
        }

        float[] result = new float[size * size];
        for (int y = 0; y < size; y++) {
            for (int x = 0; x < size; x++) {
                float maxVal = depth[y * size + x];
                for (int dy = -1; dy <= 1; dy++) {
                    for (int dx = -1; dx <= 1; dx++) {
                        int ny = Math.min(Math.max(y + dy, 0), size - 1);
                        int nx = Math.min(Math.max(x + dx, 0), size - 1);
                        float v = depth[ny * size + nx];
                        if (v > maxVal) maxVal = v;
                    }
                }
                float ew = edgeWeight[y * size + x];
                result[y * size + x] = depth[y * size + x] * (1.0f - ew) + maxVal * ew;
            }
        }
        return result;
    }

    private float[] bilinearDownscale(float[] input, int inSize, int outSize) {
        float[] output = new float[outSize * outSize];
        float ratio = (float) inSize / outSize;
        for (int y = 0; y < outSize; y++) {
            float srcY = y * ratio;
            int y0 = (int) srcY;
            int y1 = Math.min(y0 + 1, inSize - 1);
            float fy = srcY - y0;
            for (int x = 0; x < outSize; x++) {
                float srcX = x * ratio;
                int x0 = (int) srcX;
                int x1 = Math.min(x0 + 1, inSize - 1);
                float fx = srcX - x0;
                float v00 = input[y0 * inSize + x0];
                float v10 = input[y0 * inSize + x1];
                float v01 = input[y1 * inSize + x0];
                float v11 = input[y1 * inSize + x1];
                float top = v00 * (1 - fx) + v10 * fx;
                float bot = v01 * (1 - fx) + v11 * fx;
                output[y * outSize + x] = top * (1 - fy) + bot * fy;
            }
        }
        return output;
    }



    private float[] emaNormalize(float[] depth, int size) {
        float frameMin = Float.MAX_VALUE, frameMax = Float.MIN_VALUE;
        for (float v : depth) {
            if (v < frameMin) frameMin = v;
            if (v > frameMax) frameMax = v;
        }

        if (!emaInitialized) {
            emaMin = frameMin;
            emaMax = frameMax;
            emaInitialized = true;
        } else {
            emaMin = EMA_DECAY * emaMin + (1.0f - EMA_DECAY) * frameMin;
            emaMax = EMA_DECAY * emaMax + (1.0f - EMA_DECAY) * frameMax;
        }

        if (emaInitialized && smoothedDepthFloat != null) {
            float[] result = new float[depth.length];
            double totalDiff = 0.0;
            for (int i = 0; i < depth.length; i++) {
                totalDiff += Math.abs(depth[i] - smoothedDepthFloat[i]);
            }
            double meanDiff = totalDiff / depth.length;
            float alpha;
            if (meanDiff > 0.08f) {
                alpha = 1.0f;
            } else if (meanDiff > 0.005f) {
                alpha = (float) ((meanDiff - 0.005) / 0.075);
            } else {
                alpha = 0.0f;
            }
            for (int i = 0; i < depth.length; i++) {
                result[i] = smoothedDepthFloat[i] * (1.0f - alpha) + depth[i] * alpha;
            }
            smoothedDepthFloat = result;
            return result;
        }

        smoothedDepthFloat = depth.clone();
        return depth;
    }

    private void applyUiMask(byte[] depthBytes) {
        int size = DEPTH_SIZE;
        float varianceThresh = 0.001f;
        float edgeThresh = 0.05f;
        int convergenceByte = 115;

        for (int y = 3; y < size - 3; y++) {
            for (int x = 3; x < size - 3; x++) {
                float mu = 0.0f;
                float mu2 = 0.0f;
                for (int dy = -2; dy <= 2; dy++) {
                    for (int dx = -2; dx <= 2; dx++) {
                        float d = (depthBytes[(y + dy) * size + (x + dx)] & 0xFF) / 255.0f;
                        mu += d;
                        mu2 += d * d;
                    }
                }
                mu /= 25.0f;
                mu2 /= 25.0f;
                float variance = mu2 - mu * mu;
                if (variance > varianceThresh) continue;

                int edgeCount = 0;
                for (int a = 0; a < 16; a++) {
                    double angle = a * Math.PI * 2.0 / 16.0;
                    int rx = x + (int) Math.round(Math.cos(angle) * 5.0);
                    int ry = y + (int) Math.round(Math.sin(angle) * 5.0);
                    if (rx < 0 || rx >= size || ry < 0 || ry >= size) continue;
                    float dRing = (depthBytes[ry * size + rx] & 0xFF) / 255.0f;
                    if (Math.abs(dRing - mu) > edgeThresh) edgeCount++;
                }
                if (edgeCount / 16.0f > 0.5f) {
                    depthBytes[y * size + x] = (byte) convergenceByte;
                }
            }
        }
    }

    public synchronized void close() {
        if (tfliteMidas != null) {
            tfliteMidas.close();
            tfliteMidas = null;
        }
        if (tfliteDepthAnything != null) {
            tfliteDepthAnything.close();
            tfliteDepthAnything = null;
        }
        activeInterpreter = null;
        initialized = false;
        executor.shutdownNow();
    }

    public int getModelSize() {
        return DEPTH_SIZE;
    }

    public boolean isInitialized() {
        return initialized;
    }

    private MappedByteBuffer loadModelFile(String filename) throws IOException {
        AssetFileDescriptor fd = appContext.getAssets().openFd(filename);
        FileInputStream is = new FileInputStream(fd.getFileDescriptor());
        FileChannel ch = is.getChannel();
        long offset = fd.getStartOffset();
        long length = fd.getDeclaredLength();
        return ch.map(FileChannel.MapMode.READ_ONLY, offset, length);
    }
}
