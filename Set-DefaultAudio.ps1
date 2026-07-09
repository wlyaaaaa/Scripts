# Set-DefaultAudio.ps1
# Forces the default playback (and communication) device to the on-board speaker
# output, regardless of what Bluetooth / HDMI / virtual sound cards try to grab.
# Runs as a STANDARD USER - no administrator / UAC required.
#
# Target endpoint: Realtek HD Audio 2nd output
$TargetId = '{0.0.0.00000000}.{3169AA12-A867-4C30-99EC-2E55C4693109}'

Add-Type -ErrorAction Stop @'
using System;
using System.Runtime.InteropServices;
[Guid("f8679f50-850a-41cf-9c72-430f290290c8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IPolicyConfig {
    int GetMixFormat(string p, IntPtr f);
    int GetDeviceFormat(string p, bool b, IntPtr f);
    int ResetDeviceFormat(string p);
    int SetDeviceFormat(string p, IntPtr e, IntPtr m);
    int GetProcessingPeriod(string p, bool b, IntPtr d, IntPtr m);
    int SetProcessingPeriod(string p, IntPtr d);
    int GetShareMode(string p, IntPtr m);
    int SetShareMode(string p, IntPtr m);
    int GetPropertyValue(string p, bool b, IntPtr k, IntPtr v);
    int SetPropertyValue(string p, bool b, IntPtr k, IntPtr v);
    int SetDefaultEndpoint(string p, int role);
    int SetEndpointVisibility(string p, bool b);
}
[ComImport, Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9")]
class CPolicyConfigClient { }
public static class AudioSwitch {
    public static int Set(string id) {
        var cfg = (IPolicyConfig)(new CPolicyConfigClient());
        int r = 0;
        for (int role = 0; role < 3; role++) {   // eConsole, eMultimedia, eCommunications
            int x = cfg.SetDefaultEndpoint(id, role);
            if (x != 0) r = x;
        }
        return r;
    }
}
'@

$rc = [AudioSwitch]::Set($TargetId)
if ($rc -eq 0) { "OK: default output set to Realtek HD Audio 2nd output" }
else {
    "ERR: SetDefaultEndpoint returned 0x{0:X8}" -f $rc
    exit 1
}
