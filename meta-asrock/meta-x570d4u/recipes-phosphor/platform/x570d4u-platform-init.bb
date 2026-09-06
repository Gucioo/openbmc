SUMMARY = "Platform init bits the X570D4U device tree does not cover"
DESCRIPTION = "vbat-enable holds the board's 'output-hwm-vbat-enable' GPIO asserted; without \
it the VBAT divider is gated off and ADC channel 9 reads ~0 mV instead of the CMOS battery \
voltage. \
\
Note there is deliberately no service here to instantiate i2c sensors: hwmontempsensor \
creates them itself from the entity-manager configuration (front panel TMP75 at i2c-0 0x4d \
and the on-DIMM JC42s at i2c-7 0x1a/0x1b). Earlier versions of this recipe did, and fought \
the daemon for the devices -- the log fills with 'Failed to instantiate' and sensors come \
and go. The same applies to psusensor and the PSU's pmbus device."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

inherit systemd

SRC_URI = "file://vbat-enable.service"

RDEPENDS:${PN} = "libgpiod-tools"

SYSTEMD_SERVICE:${PN} = "vbat-enable.service"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/vbat-enable.service ${D}${systemd_system_unitdir}
}
