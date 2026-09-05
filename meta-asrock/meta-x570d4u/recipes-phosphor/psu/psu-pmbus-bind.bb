SUMMARY = "PSU fan floor for the Supermicro PWS-441P-1H on the X570D4U-2L2T"
DESCRIPTION = "This PSU follows the PMBus AC/DC Server Power application profile, which \
fixes FAN_COMMAND_1's linear exponent at N=0. The kernel pmbus driver writes ordinary \
LINEAR11 with a computed exponent, so the target psusensor writes is read by the PSU as a \
huge duty cycle and pins the fan near 13000 RPM; FAN_COMMAND_1 can only increase fan speed, \
so it never recovers. This guard re-asserts a correctly encoded floor. \
\
Note: do NOT add a service that instantiates the pmbus device at 0x3c -- psusensor creates \
and deletes that device itself, and a second owner makes them fight, leaving the device \
repeatedly torn down."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

inherit systemd

SRC_URI = "file://psu-fan-release.service \
           file://psu-fan-release \
           "

RDEPENDS:${PN} = "i2c-tools"

SYSTEMD_SERVICE:${PN} = "psu-fan-release.service"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/psu-fan-release.service ${D}${systemd_system_unitdir}
    install -d ${D}${bindir}
    install -m 0755 ${UNPACKDIR}/psu-fan-release ${D}${bindir}/psu-fan-release
}
