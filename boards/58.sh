# Wiren Board 5.8
export FORCE_WB_VERSION=58

board_include soc_imx28.sh

board_install() {
	install_wb5_packages
	set_fdt imx28-wirenboard58
}
