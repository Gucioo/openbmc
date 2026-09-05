SUMMARY = "Platform init bits the X570D4U device tree does not cover"
DESCRIPTION = "vbat-enable holds the board's 'output-hwm-vbat-enable' GPIO asserted; \
without it the VBAT divider is gated off and ADC channel 9 reads ~0 mV instead of the \
CMOS battery voltage. frontpanel-temp-bind instantiates the TMP75/LM75-compatible \
sensor on the AUX_PANEL1 SMBus (i2c-0, 0x4d), as provided by a Chenbro RM238 front \
panel -- entity-manager only instantiates EEPROMs and the device tree declares nothing \
on that bus. dimm-temp-bind does the same for the on-DIMM JC42/TSE2004 sensors at \
i2c-7 0x1a/0x1b."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

inherit systemd

SRC_URI = "file://vbat-enable.service \
           file://frontpanel-temp-bind.service \
           file://dimm-temp-bind.service \
           "

RDEPENDS:${PN} = "libgpiod-tools i2c-tools"

SYSTEMD_SERVICE:${PN} = "vbat-enable.service frontpanel-temp-bind.service dimm-temp-bind.service"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/vbat-enable.service ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/frontpanel-temp-bind.service ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/dimm-temp-bind.service ${D}${systemd_system_unitdir}
}
