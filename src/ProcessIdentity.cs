using System;
using System.Runtime.InteropServices;
using System.Text;

namespace ChatGPTWindowsInstaller
{
    public sealed class ProcessIdentity
    {
        public string FamilyName = "";
        public string ImagePath = "";

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(uint access, bool inherit, int processId);
        [DllImport("kernel32.dll")]
        private static extern bool CloseHandle(IntPtr handle);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern int GetPackageFamilyName(IntPtr process, ref uint length, StringBuilder name);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool QueryFullProcessImageName(IntPtr process, uint flags, StringBuilder path, ref uint size);

        public static ProcessIdentity Read(int processId)
        {
            var result = new ProcessIdentity();
            // Limited query access does not require reading another process's modules/memory.
            IntPtr handle = OpenProcess(0x1000, false, processId);
            if (handle == IntPtr.Zero) return result;
            try
            {
                uint length = 0;
                if (GetPackageFamilyName(handle, ref length, null) == 122 && length > 0 && length <= 1024)
                {
                    var name = new StringBuilder((int)length);
                    if (GetPackageFamilyName(handle, ref length, name) == 0) result.FamilyName = name.ToString();
                }
                if (result.FamilyName.Length == 0)
                {
                    uint size = 32768;
                    var path = new StringBuilder((int)size);
                    if (QueryFullProcessImageName(handle, 0, path, ref size)) result.ImagePath = path.ToString();
                }
            }
            finally { CloseHandle(handle); }
            return result;
        }
    }
}
