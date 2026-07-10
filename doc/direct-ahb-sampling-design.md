# Direct AHardwareBuffer Sampling Design

- **Status:** Deferred pending an Android/Quest build and Vulkan-validation loop
- **Branch:** `perf/remove-rgba-compute-copy`
- **Base:** `perf/cache-ahb-imports` (`e46b0a1`)

## Goal

Remove the intermediate full-resolution RGBA compute texture from the Android MediaCodec path. The desired steady-state path is:

```text
MediaCodec → AImageReader/AHardwareBuffer → final Godot display/composition pass
```

Today the path is:

```text
MediaCodec
  → AImageReader/AHardwareBuffer
  → Vulkan YCbCr sample
  → full-resolution RGBA compute write
  → Godot canvas/composition sample
```

At 3840×2160 and 72 FPS, the intermediate RGBA image accounts for about 2.39 GB/s of logical writes before later texture reads, tiling, and cache effects. Removing it remains a high-value performance target.

## Why this is deferred

The current compute pass is not only a color-conversion step. It is also the adapter that joins the imported external-format image to its special Vulkan YCbCr sampler. Removing the pass safely requires renderer and synchronization capabilities that the current custom Godot patch does not provide.

A minimal implementation that places the imported RenderingDevice RID in a `Texture2DRD` is invalid for two independent reasons:

1. Vulkan requires an identically defined `VkSamplerYcbcrConversion` on the image view and sampler, with the conversion sampler immutable in the shader pipeline layout. Godot's normal CanvasItem/material sampler is compiled independently of the runtime texture RID.
2. Returning the acquired `AImage` to `AImageReader` without a GPU release fence allows MediaCodec to rewrite the same buffer while a later display pass still samples it. Retaining an `AHardwareBuffer` reference keeps the object alive but does not reserve its BufferQueue slot.

The current development environment has no Android NDK/vcpkg toolchain or Quest device validation. Implementing the renderer and fence changes without compilation, Vulkan validation, or on-device testing would knowingly risk invalid descriptors, color errors, corruption, or decoder/GPU races.

## Required correctness contract

A direct-sampling implementation must provide one application-facing operation:

```text
present_decoded_frame(frame_token, buffer_identity, generation, metadata)
```

The implementation behind that interface owns all of the following details:

- acquire-fence handling;
- AHB import caching;
- external-format and memory metadata;
- YCbCr conversion and immutable sampler selection;
- image layout and foreign queue-family ownership;
- stable Godot display texture publication;
- release-fence export;
- acquired `AImage` retirement;
- generation invalidation and cache eviction.

`StreamConnection` should select frames and generations, but should not manage Vulkan pipeline layouts, samplers, descriptor sets, or GPU fences directly.

## Vulkan import requirements

For each distinct AHB, the engine integration must:

1. Query `VkAndroidHardwareBufferPropertiesANDROID` with `VkAndroidHardwareBufferFormatPropertiesANDROID` chained through `pNext`.
2. Validate sampled-image support and choose chroma filtering only from advertised format features.
3. Use the queried `allocationSize` and `memoryTypeBits`.
4. Import image AHB memory with both:
   - `VkImportAndroidHardwareBufferInfoANDROID`;
   - `VkMemoryDedicatedAllocateInfo` naming the imported image.
5. For an external-format image:
   - use `VK_FORMAT_UNDEFINED`;
   - chain `VkExternalFormatANDROID` into image creation;
   - use sampled-image usage only unless additional usage is explicitly supported;
   - create a 2D, one-mip, one-layer image.
6. Create `VkSamplerYcbcrConversion` with the same external-format identifier.
7. Use the queried suggested model, range, component mapping, and chroma offsets unless an explicitly validated stream-metadata override is required.
8. Chain an identically defined conversion into both the image view and sampler.
9. Use clamp-to-edge, normalized coordinates, no anisotropy, and supported filtering.
10. Bind the conversion sampler as an immutable sampler in the shader pipeline layout.

The current `patches/godot-4.7-ahb.patch` does not yet satisfy all of these requirements. In particular, it hardcodes BT.709 narrow range, does not attach the conversion to the image view, does not chain the external format into conversion creation, ignores queried allocation metadata, and exposes the image as a fictitious RGBA format.

## Required Godot renderer integration

### Rejected approach: ordinary `Texture2DRD`

`Texture2DRD` provides a useful stable RenderingServer texture wrapper, but it carries only a texture RID. Canvas and spatial material pipelines choose their immutable samplers when the shader pipeline layout is created. Swapping an external YCbCr RID into that wrapper cannot retroactively replace the pipeline's normal sampler with a conversion-compatible immutable sampler.

Overriding only the descriptor write is insufficient: the sampler must already be immutable in the descriptor-set layout.

### Recommended approach: dedicated external-video texture path

Add a renderer-level external-video abstraction to the custom Godot build. It should:

- associate an imported image view with a generation-scoped YCbCr conversion definition;
- select or build a compatible shader/pipeline-layout variant containing the immutable conversion sampler;
- expose a stable Texture2D-compatible resource to the application;
- work for every current consumer:
  - the stream viewport CanvasItem;
  - the 3D screen material;
  - mono and stereo OpenXR composition-layer materials;
- change the current buffer without changing resource ownership or material parameters;
- retire old descriptor/image state only after GPU completion.

The renderer may share one conversion/sampler definition across all AHBs in a generation when their queried external format and suggested conversion parameters are identical. Each image view may use a separate but identically defined conversion. Pipeline variants must be keyed by every property that affects layout compatibility.

A new shader hint or texture type may be appropriate, but it must be implemented at the shader compiler, material storage, descriptor-set layout, and renderer binding layers together. A driver-only descriptor override is not sufficient.

## Producer/consumer synchronization

### Acquire

Use `AImageReader_acquireLatestImageAsync` (or the appropriate async acquisition API for the supported API level) to obtain an acquire fence.

Before the first sample of that image:

1. wait for the acquire fence, preferably by importing its sync FD as a temporary Vulkan semaphore;
2. transfer ownership from `VK_QUEUE_FAMILY_FOREIGN_EXT` to the Godot graphics queue where required;
3. transition the image to the shader-read layout.

A CPU wait can be used as an initial correctness fallback, but it must be measured because it can move synchronization latency onto the decode/render path.

### Release

After the final display/composition sample of an image:

1. transition/release ownership back to `VK_QUEUE_FAMILY_FOREIGN_EXT` where required;
2. signal an exportable binary semaphore;
3. export a `SYNC_FD`;
4. pass that FD to `AImage_deleteAsync`.

The `AImage` becomes invalid immediately after `AImage_deleteAsync`; the BufferQueue uses the fence to delay producer reuse until GPU reads finish.

Neither a render-thread callback nor `AHardwareBuffer_acquire` proves GPU completion. A fixed number of delayed frames is also not a correctness mechanism.

## Ownership model

### Acquired frame token

Owns until asynchronous release:

- `AImage *`;
- the per-frame AHB reference currently acquired by `AndroidMediaCodec`;
- acquire fence FD;
- PTS, dimensions, generation, and buffer identity.

### Import-cache entry

Owns until buffer removal or generation retirement:

- stable AHB identity;
- retained AHB reference for object/key lifetime;
- imported image and memory;
- image view/conversion association;
- renderer external-video resource state.

The import cache does **not** own the acquired frame token and does not make a returned `AImage` safe to sample.

### Display resource

The stable application-visible texture is a consumer of cache entries. It must not free imported RIDs. Cache retirement must first detach or replace the displayed image, wait for GPU completion, then destroy renderer/Vulkan objects and release the retained AHB.

## Color conversion

The current compute shader supports Rec.601, Rec.709, Rec.2020, full range, and limited range. Removing it must not silently reduce support to hardcoded Rec.709 limited range.

The direct path must define one conversion owner:

- Prefer the AHB's queried Vulkan suggested model/range/chroma offsets for external-format sampling.
- Read and preserve `AImage_getDataSpace` when available.
- Verify how Sunshine/MediaCodec stream metadata maps to the produced AHB dataspace.
- Handle transfer function and gamut separately when YCbCr model/range alone is insufficient.
- Validate Rec.601/709/2020 and full/limited streams with known test patterns.

Do not apply conversion in both Vulkan sampling and the final shader.

## Reconfiguration and shutdown

A generation change must occur in this order:

1. stop admitting old-generation frames;
2. detach the old displayed image;
3. submit release work for every acquired image;
4. retire renderer descriptors and imports after GPU completion;
5. release retained AHB references;
6. destroy the old ImageReader/codec;
7. create and warm the new generation independently.

No queued callback may retain a raw `StreamConnection *` after destruction.

## Proposed implementation stages

### Stage 1: validation harness

- Install the Android NDK/vcpkg toolchain.
- Build both patched Godot templates and the GDExtension.
- Enable Vulkan validation on a supported Android test device.
- Add a focused external-video test scene independent of Moonlight streaming.
- Log AHB format properties, external format, model/range, chroma offsets, descriptor count, and feature flags.

### Stage 2: correct AHB import and fences

- Correct the existing AHB import metadata and dedicated allocation.
- Add async ImageReader acquisition and acquire-fence handling.
- Add foreign queue-family ownership transfers.
- Add release semaphore export and `AImage_deleteAsync`.
- Keep the compute output temporarily so synchronization can be validated separately.

### Stage 3: renderer external-video abstraction

- Add the dedicated immutable-sampler pipeline/layout path.
- Add a stable application-visible external-video texture resource.
- Verify CanvasItem, 3D screen, mono composition, and stereo composition consumers.
- Make unsupported renderer/device combinations fail explicitly.

### Stage 4: remove the intermediate copy

- Publish imported frames directly through the external-video resource.
- Remove `rgba_output_tex_`, compute shader, compute pipeline, uniform sets, push constants, and dispatch callbacks.
- Delete `ycbcr_to_rgba.comp`, its SPIR-V, and generated header.
- Preserve the FFmpeg/software and local-capture paths.

### Stage 5: measure

Compare before/after on the same stream and headset:

- CPU time in decode and render threads;
- GPU frame time;
- memory bandwidth/counters where available;
- missed frames and compositor timing;
- end-to-end latency;
- memory stability across reconnect/reconfigure cycles.

## Acceptance criteria

- No Vulkan validation errors for import, conversion, descriptor layouts, synchronization, ownership, or destruction.
- No sampling before the acquire fence signals.
- No AImage is returned without a release fence covering its final GPU read.
- Cache misses plateau near the ImageReader pool size.
- No intermediate full-resolution RGBA texture or compute dispatch exists in the MediaCodec path.
- Correct color for Rec.601/709/2020 and full/limited test streams.
- Correct output in viewport, 3D screen, mono composition, and stereo composition modes.
- Stable memory and resource counts across repeated stop/start and resolution/codec changes.
- Measurable frame-time or power improvement on Quest hardware.

## Official references

- [VK_ANDROID_external_memory_android_hardware_buffer](https://registry.khronos.org/vulkan/specs/latest/man/html/VK_ANDROID_external_memory_android_hardware_buffer.html)
- [VkAndroidHardwareBufferFormatPropertiesANDROID](https://registry.khronos.org/vulkan/specs/latest/man/html/VkAndroidHardwareBufferFormatPropertiesANDROID.html)
- [VkSamplerYcbcrConversionCreateInfo](https://registry.khronos.org/vulkan/specs/latest/man/html/VkSamplerYcbcrConversionCreateInfo.html)
- [VkSamplerYcbcrConversionInfo](https://registry.khronos.org/vulkan/specs/latest/man/html/VkSamplerYcbcrConversionInfo.html)
- [VkImageViewCreateInfo](https://registry.khronos.org/vulkan/specs/latest/man/html/VkImageViewCreateInfo.html)
- [VkWriteDescriptorSet](https://registry.khronos.org/vulkan/specs/latest/man/html/VkWriteDescriptorSet.html)
- [VkImportAndroidHardwareBufferInfoANDROID](https://registry.khronos.org/vulkan/specs/latest/man/html/VkImportAndroidHardwareBufferInfoANDROID.html)
- [VkImportSemaphoreFdInfoKHR](https://registry.khronos.org/vulkan/specs/latest/man/html/VkImportSemaphoreFdInfoKHR.html)
- [vkGetSemaphoreFdKHR](https://registry.khronos.org/vulkan/specs/latest/man/html/vkGetSemaphoreFdKHR.html)
- [Android NDK Media APIs (`AImage`, `AImageReader`)](https://developer.android.com/ndk/reference/group/media)
- [Android NDK `AHardwareBuffer` APIs](https://developer.android.com/ndk/reference/group/a-hardware-buffer)
