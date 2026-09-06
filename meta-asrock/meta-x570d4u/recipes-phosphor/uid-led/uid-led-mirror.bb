SUMMARY = "Publish the X570D4U identify (UID) LED state on D-Bus"
DESCRIPTION = "bmcweb renders Redfish LocationIndicatorActive from the Asserted property of \
xyz.openbmc_project.Led.Group at /xyz/openbmc_project/led/groups/enclosure_identify. This \
board gives the BMC no way to drive its identify LED -- only to read the latch state and to \
emulate a front panel button press, and asserting the latter reliably hangs the BMC. So this \
publishes the state read-only and leaves control to the physical button."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

inherit systemd pkgconfig

DEPENDS = "systemd libgpiod"
RDEPENDS:${PN} = "libgpiod"

SRC_URI = "file://uid-led-mirror.c \
           file://uid-led-mirror.service \
           "

SYSTEMD_SERVICE:${PN} = "uid-led-mirror.service"

# Build from S with a relative source name so debug info does not capture build paths.
S = "${UNPACKDIR}"

do_compile() {
    cd ${S}
    ${CC} ${CFLAGS} ${LDFLAGS} -o uid-led-mirror uid-led-mirror.c \
        $(pkg-config --cflags --libs libsystemd libgpiod)
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${S}/uid-led-mirror ${D}${bindir}/uid-led-mirror
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/uid-led-mirror.service ${D}${systemd_system_unitdir}
}
