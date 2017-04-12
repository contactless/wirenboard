# Wiren Board Zero rev 5.8+
export FORCE_WB_VERSION=58

. ${SCRIPT_DIR}/boards/include/soc_imx28.sh

board_install() {
	chr_apt wb-mqtt-homeui wb-homa-adc wb-rules wb-rules-system netplug wb-test-suite wb-hwconf-manager

	set_fdt imx28-wirenboard58

	JSON=${OUTPUT}/etc/wb-hardware.conf
	json_edit '.slots|=map(select(.id !="wb58-mod1"))'
	json_edit '.slots|=map(select(.id !="wb58-mod2"))'

	for extio_n in {1..8}; do
		json_edit '.slots|=map(select(.id !="wb5-extio'${extio_n}'"))'
	done

	json_edit '.slots|=map(if .id=="wb55-gsm" then .module="wb56-mod-rtc" else . end)'
	json_edit '.slots|=map(if .id=="wb5-eth" then .module="" else . end)'

	# disable 1-wire drivers to prevent floating pin from picking noise

	echo "blacklist w1_gpio" > ${OUTPUT}/etc/modprobe.d/wirenboard-zero-w1.conf
}
