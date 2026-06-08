class_name WolSender
extends RefCounted

func send_wol(mac_address: String, broadcast_ip: String = "255.255.255.255", port: int = 9) -> bool:
	var mac_bytes = _mac_to_bytes(mac_address)
	if mac_bytes.size() != 6:
		return false
	var payload = PackedByteArray()
	for i in range(6):
		payload.append(0xFF)
	for i in range(16):
		payload.append_array(mac_bytes)
	var udp = PacketPeerUDP.new()
	udp.set_broadcast_enabled(true)
	var err = udp.set_dest_address(broadcast_ip, port)
	if err != OK:
		udp.close()
		return false
	err = udp.put_packet(payload)
	var sent_broadcast = (err == OK)
	udp.close()
	return sent_broadcast

func send_wol_to_host(mac_address: String, host_ip: String) -> bool:
	var result = send_wol(mac_address, "255.255.255.255", 9)
	send_wol(mac_address, "255.255.255.255", 47009)
	if not host_ip.is_empty():
		send_wol(mac_address, host_ip, 9)
	return result

func _mac_to_bytes(mac: String) -> PackedByteArray:
	var clean = mac.replace(":", "").replace("-", "").replace(" ", "").replace(".", "")
	if clean.length() != 12:
		return PackedByteArray()
	var result = PackedByteArray()
	for i in range(6):
		var byte_str = clean.substr(i * 2, 2)
		var val = byte_str.hex_to_int()
		if val < 0:
			return PackedByteArray()
		result.append(val)
	return result
