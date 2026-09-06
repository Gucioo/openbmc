# The web UI's Overview and Power pages read PowerControl/PowerConsumedWatts from the
# legacy /redfish/v1/Chassis/<id>/Power resource. bmcweb disables that by default in
# favour of PowerSubsystem, so those panels stay empty. The PSU publishes true total AC
# input power (READ_PIN) as the "total_power" sensor, which is what this resource reports.
PACKAGECONFIG:append:x570d4u = " redfish-allow-deprecated-power-thermal"
