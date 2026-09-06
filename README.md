# OpenBMC for the ASRock Rack X570D4U-2L2T

This is a fork of [OpenBMC](https://github.com/openbmc/openbmc) carrying board support for
the **ASRock Rack X570D4U / X570D4U-2L2T**, developed against a real machine: an X570D4U-2L2T
in a Chenbro RM238 chassis with a Supermicro PWS-441P-1H power supply.

Upstream ships an entity-manager config for the x470d4u but nothing for this board, so a
stock build reports **no sensors at all**. This fork adds the sensor bring-up, PSU support
over PMBus, working fan control, a read-only identify LED, a dark web UI, and a device tree
fix for the fan tachometers.

* **Board support layer:** [`meta-asrock/meta-x570d4u/`](meta-asrock/meta-x570d4u/) --
  [full README with every finding](meta-asrock/meta-x570d4u/README.md) and
  [specification references](meta-asrock/meta-x570d4u/docs/REFERENCES.md)
* **Ready-to-flash image:** see [Releases](https://github.com/Gucioo/openbmc/releases)
* **Branch:** `x570d4u-2l2t-support`

Everything below is measured on hardware unless stated otherwise. Where upstream is wrong,
that is called out with the evidence.

## What works

39 sensors -- 13 voltage rails, CPU and board temperatures, front-panel and on-DIMM
temperatures, VBAT, six fan tachometers and six fan PWMs. Full PSU telemetry over PMBus with
no address translator. Fan control on all six headers driven by a temperature curve. PSU in
Redfish inventory, `PowerConsumedWatts` from the PSU's true AC input, identify LED state in
Redfish, and a dark web UI including the login page.

## Fan header, PWM and tachometer mapping

The stock device tree gets this wrong, so a patch is carried in
[`recipes-kernel/linux/`](meta-asrock/meta-x570d4u/recipes-kernel/linux/). It never enables
tach channel 3, so the **FAN4 header reports no tachometer at all** even with a known-good
fan -- unplugging the fan changes nothing, because nothing was reading it. The primary
channels for FAN5 and FAN6 are also swapped.

Measured by running each fan alone at full duty with every other fan stopped, then confirming
against the silkscreen by watching which fan spins:

| Header | PWM channel | sysfs | tach channel | sysfs | RPM at full duty |
|---|---|---|---|---|---|
| FAN1 | 0 | `pwm1` | 0 | `fan1_input` | 2445 |
| FAN2 | 1 | `pwm2` | 1 | `fan2_input` | 2614 |
| FAN3 | 2 | `pwm3` | 2 | `fan3_input` | 2549 |
| FAN4 | 3 | `pwm4` | 3 | `fan4_input` | 2453 |
| FAN5 | 5 | `pwm6` | 4 | `fan5_input` | 2573 |
| FAN6 | 4 | `pwm5` | 5 | `fan6_input` | 2241 |

Channels 0-3 are a straight 1:1 with the PWM channels; **FAN5 and FAN6 are crossed**. FAN1
and FAN2 are 4-pin headers; FAN4, FAN5 and FAN6 are 6-pin dual-fan connectors whose second
position (channels 11, 12, 13) is untested here.

## Findings that apply beyond this board

These cost real time to find, and most are not documented anywhere obvious.

**A Supermicro PSU's fan pins at ~13000 RPM under Linux.** The PMBus Application Profile for
AC/DC Server Power Supplies fixes `FAN_COMMAND_1`'s exponent at N=0, but the kernel `pmbus`
driver writes ordinary LINEAR11 with a computed exponent. A target of 30 leaves as `0xdbc0`;
the PSU ignores the exponent, reads mantissa 960, and treats it as 960% duty. The command can
only ever *increase* fan speed, so it never recovers and `CLEAR_FAULTS` does not help.

**Fan PWM objects come from a connector, not from fan detection.** dbus-sensors creates
`/xyz/openbmc_project/control/fanpwm/*` only when the entity-manager fan config carries a
`Connector`. Without one, an `AspeedFan` yields a tach sensor and no PWM target, and
`phosphor-fan-control` logs *"No service for ... Control.FanPwm"* and retries every two
seconds **forever** -- about 43k journal lines a day into a RAM-backed journal.

**Never instantiate an i2c device that a dbus-sensors daemon owns.** `hwmontempsensor` creates
TMP75 and JC42 devices itself, and `psusensor` creates the PSU's pmbus device. Adding a
systemd unit that writes to `new_device` makes them fight, and sensors appear and vanish.

**Files copied onto a running BMC shadow the image permanently.** The rootfs is an overlay and
a firmware update rewrites only the read-only half, so anything ever `scp`ed into `/usr`
survives every subsequent flash and silently wins. A flash appears to succeed, the version
string changes, and your old test file is still in place. Check
`find /run/initramfs/rw/cow/usr -type f` after flashing.

**`fanctl` is broken upstream and fixed here.** `control/fanctl.cpp` registers a positional
option named `"fan list"`, with a space, which CLI11 rejects while the command tree is being
built -- so every invocation fails with *"Invalid positional Name: fan list"* before parsing,
including `fanctl get`. One-character fix, carried as a patch.

**Thermal profiles cannot key on `Control.ThermalMode`.** `Manager::load()` evaluates
`profiles.json` before constructing zones, but the zone is what hosts that object, so the
profile's lookup throws and fan control exits 1 on every boot. Verified on hardware. Two
further traps: `Current` is stored upper-cased, so a profile must match `"QUIET"` not
`"Quiet"` or it silently never matches, and only values in the zone's `Supported` list are
accepted.

**Redfish `LocationIndicatorActive` needs four things**, only discoverable from bmcweb's
source: a service publishing `Led.Group`, an object manager, ownership of the hardcoded name
`xyz.openbmc_project.LED.GroupManager`, and an `identifying` association from a chassis that
implements `Item.Chassis`, `Item.Panel` or `Item.Board.Motherboard`. Miss the last and bmcweb
skips the lookup with nothing logged.

**An `ExternalSensor` cannot produce a visible percent sensor.** It derives its D-Bus
namespace from `Units` alone, and while `"Percent"` maps to `.../sensors/percent/`, bmcweb's
sensor collection does not enumerate that namespace -- the sensor would be correctly labelled
and completely invisible. A percent reading has to be published by a daemon that owns the
object under `fan_pwm` directly.

**The web UI has no fan control, and its Sensors page never live-updates.** Neither is
disabled -- both are absent by design. See the
[layer README](meta-asrock/meta-x570d4u/README.md) for the measurements behind that.

**Dark mode is mostly free.** Bootstrap 5.3's dark theme is already compiled into webui-vue;
it needs `data-bs-theme="dark"` on `<html>` plus overrides for the ~28 rules that hardcode
light colours, including one that forces `color:#161616!important` on every label and would
otherwise render label text invisible. Avoid Vue scoped-hash selectors -- they change on
every rebuild.

## Build notes

GCC 12 or newer is required: `nodejs-native` bundles `ada`, which uses C++20 `constexpr
std::string`, and libstdc++ only implements that from GCC 12. A full build does not fit
comfortably in 100 GB, so add `INHERIT += "rm_work"`.

Flashing over Redfish needs an explicit content type, or bmcweb answers 400 and creates no
task:

```
curl -k -u root:<password> -X POST \
  -H "Content-Type: application/octet-stream" \
  -T obmc-phosphor-image-x570d4u-<build>.static.mtd.tar \
  https://<bmc-ip>/redfish/v1/UpdateService/update
```

## Credits

Board bring-up follows the trail cut by [Renze Nicolai](https://nicolaielectronics.nl/blog/openbmc-x570d4u/),
whose X570D4U port is the basis of the fan control configuration here, and by
[Mrkvak](https://github.com/Mrkvak/homelab) on running a Supermicro PSU with an ASRock Rack
board.

---

# OpenBMC

[![Build Status](https://jenkins.openbmc.org/buildStatus/icon?job=latest-master)](https://jenkins.openbmc.org/job/latest-master/)

OpenBMC is a Linux distribution for management controllers used in devices such
as servers, top of rack switches or RAID appliances. It uses
[Yocto](https://www.yoctoproject.org/),
[OpenEmbedded](https://www.openembedded.org/wiki/Main_Page),
[systemd](https://www.freedesktop.org/wiki/Software/systemd/), and
[D-Bus](https://www.freedesktop.org/wiki/Software/dbus/) to allow easy
customization for your platform.

## Setting up your OpenBMC project

### 1) Prerequisite

See the
[Yocto documentation](https://docs.yoctoproject.org/ref-manual/system-requirements.html#required-packages-for-the-build-host)
for the latest requirements

#### Ubuntu

```sh
sudo apt install git gcc g++ make file wget \
    gawk diffstat bzip2 cpio chrpath zstd lz4 bzip2
```

#### Fedora

```sh
sudo dnf install git python3 gcc g++ gawk which bzip2 chrpath cpio \
    hostname file diffutils diffstat lz4 wget zstd rpcgen patch
```

### 2) Download the source

```sh
git clone https://github.com/openbmc/openbmc
cd openbmc
```

### 3) Target your hardware

Any build requires an environment set up according to your hardware target.
There is a special script in the root of this repository that can be used to
configure the environment as needed. The script is called `setup` and takes the
name of your hardware target as an argument.

The script needs to be sourced while in the top directory of the OpenBMC
repository clone, and, if run without arguments, will display the list of
supported hardware targets, see the following example:

```text
$ . setup <machine> [build_dir]
Target machine must be specified. Use one of:
...
```

A more complete list of supported machines can be found under
[meta-phosphor/docs](https://github.com/openbmc/openbmc/blob/master/meta-phosphor/docs/supported-machines.md).

Once you know the target (e.g. romulus), source the `setup` script as follows:

```sh
. setup romulus
```

### 4) Build

```sh
bitbake obmc-phosphor-image
```

Additional details can be found in the [docs](https://github.com/openbmc/docs)
repository.

## OpenBMC Development

The OpenBMC community maintains a set of tutorials new users can go through to
get up to speed on OpenBMC development out
[here](https://github.com/openbmc/docs/blob/master/development/README.md)

## Build Validation and Testing

Commits submitted by members of the OpenBMC GitHub community are compiled and
tested via our [Jenkins](https://jenkins.openbmc.org/) server. Commits are run
through two levels of testing. At the repository level the makefile `make check`
directive is run. At the system level, the commit is built into a firmware image
and run with an arm-softmmu QEMU model against a barrage of
[CI tests](https://jenkins.openbmc.org/job/CI-MISC/job/run-ci-in-qemu/).

Commits submitted by non-members do not automatically proceed through CI
testing. After visual inspection of the commit, a CI run can be manually
performed by the reviewer.

Automated testing against the QEMU model along with supported systems are
performed. The OpenBMC project uses the
[Robot Framework](http://robotframework.org/) for all automation. Our complete
test repository can be found
[here](https://github.com/openbmc/openbmc-test-automation).

## Submitting Patches

Support of additional hardware and software packages is always welcome. Please
follow the
[contributing guidelines](https://github.com/openbmc/docs/blob/master/CONTRIBUTING.md)
when making a submission. It is expected that contributions contain test cases.

## Bug Reporting

[Issues](https://github.com/openbmc/openbmc/issues) are managed on GitHub. It is
recommended you search through the issues before opening a new one.

## Questions

First, please do a search on the internet. There's a good chance your question
has already been asked.

For general questions, please use the openbmc tag on
[Stack Overflow](https://stackoverflow.com/questions/tagged/openbmc). Please
review the
[discussion](https://meta.stackexchange.com/questions/272956/a-new-code-license-the-mit-this-time-with-attribution-required?cb=1)
on Stack Overflow licensing before posting any code.

For technical discussions, please see [contact info](#contact) below for Discord
and mailing list information. Please don't file an issue to ask a question.
You'll get faster results by using the mailing list or Discord.

### Will OpenBMC run on my Acme Server Corp. XYZ5000 motherboard?

This is a common question, particularly regarding boards from popular COTS
(commercial off-the-shelf) vendors such as Supermicro and ASRock. You can see
the list of supported boards by running `. setup` (with no further arguments) in
the root of the OpenBMC source tree. Most of the platforms supported by OpenBMC
are specialized servers operated by companies running large datacenters, but
some more generic COTS servers are supported to varying degrees.

If your motherboard is not listed in the output of `. setup` it is not currently
supported. Porting OpenBMC to a new platform is a non-trivial undertaking,
ideally done with the assistance of schematics and other documentation from the
manufacturer (it is not completely infeasible to take on a porting effort
without documentation via reverse engineering, but it is considerably more
difficult, and probably involves a greater risk of hardware damage).

**However**, even if your motherboard is among those listed in the output of
`. setup`, there are two significant caveats to bear in mind. First, not all
ports are equally mature -- some platforms are better supported than others, and
functionality on some "supported" boards may be fairly limited. Second, support
for a motherboard is not the same as support for a complete system -- in
particular, fan control is critically dependent on not just the motherboard but
also the fans connected to it and the chassis that the board and fans are housed
in, both of which can vary dramatically between systems using the same board
model. So while you may be able to compile and install an OpenBMC build on your
system and get some basic functionality, rough edges (such as your cooling fans
running continuously at full throttle) are likely.

See also
["Supported Machines"](https://github.com/openbmc/openbmc/blob/master/meta-phosphor/docs/supported-machines.md).

## Features of OpenBMC

### Feature List

- Host management: Power, Cooling, LEDs, Inventory, Events, Watchdog
- Full IPMI 2.0 Compliance with DCMI
- Code Update Support for multiple BMC/BIOS images
- Web-based user interface
- REST interfaces
- D-Bus based interfaces
- SSH based SOL
- Remote KVM
- Hardware Simulation
- Automated Testing
- User management
- Virtual media

### Features In Progress

- OpenCompute Redfish Compliance
- Verified Boot

### Features Requested but need help

- OpenBMC performance monitoring

## Finding out more

Dive deeper into OpenBMC by opening the [docs](https://github.com/openbmc/docs)
repository.

## Technical Oversight Forum

The Technical Oversight Forum (TOF) guides the technical direction of the project. Members are voted on by
community members based on the [membership and voting](https://github.com/openbmc/docs/blob/master/tof/membership-and-voting.md)
guidelines.

## Contact

- Mail: openbmc@lists.ozlabs.org
  [https://lists.ozlabs.org/listinfo/openbmc](https://lists.ozlabs.org/listinfo/openbmc)
- Discord: [https://discord.gg/69Km47zH98](https://discord.gg/69Km47zH98)
