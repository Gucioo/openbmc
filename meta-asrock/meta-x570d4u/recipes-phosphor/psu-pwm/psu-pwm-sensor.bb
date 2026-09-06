SUMMARY = "Publish the PSU fan duty cycle as a percent sensor"
DESCRIPTION = "The PSU's pmbus hwmon exposes fan1_target but no pwm1, so dbus-sensors' \
PwmSensor -- the code path that produces a Unit.Percent sensor under \
/xyz/openbmc_project/sensors/fan_pwm/ -- never applies to it. An entity-manager \
ExternalSensor cannot substitute: it picks its namespace from Units alone, and while \
\"Percent\" maps to /xyz/openbmc_project/sensors/percent/, bmcweb's sensor collection does \
not enumerate that namespace, so the sensor would be correctly labelled and invisible. \
This owns the object directly. psu-fan-release supplies the value through a state file so \
only one process talks PMBus."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

inherit systemd pkgconfig

DEPENDS = "systemd"

SRC_URI = "file://psu-pwm-sensor.c \
           file://psu-pwm-sensor.service \
           "

SYSTEMD_SERVICE:${PN} = "psu-pwm-sensor.service"

# Build from S with a relative source name so debug info does not capture build paths.
S = "${UNPACKDIR}"

do_compile() {
    cd ${S}
    ${CC} ${CFLAGS} ${LDFLAGS} -o psu-pwm-sensor psu-pwm-sensor.c \
        $(pkg-config --cflags --libs libsystemd) -lm
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${S}/psu-pwm-sensor ${D}${bindir}/psu-pwm-sensor
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/psu-pwm-sensor.service ${D}${systemd_system_unitdir}
}
