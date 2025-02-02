whoami /all
systeminfo
net user %username%
net localgroup
tasklist /svc
icacls "C:\Program Files"
schtasks /query /fo LIST
reg query HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall

<#

To identify **weak permissions**, **insecure services**, or **writable paths**, you need to analyze the output of the commands you run. Below are specific signs to look for and examples of how to interpret them:

---

### **1. Weak File/Folder Permissions**
Use `icacls` or manual inspection to check for **write/modify access** on sensitive files/folders.  
**Key Indicators**:
- **Your user/group** (e.g., `BUILTIN\Users`, `Everyone`, `Authenticated Users`) has **`(W)`** (write), **`(M)`** (modify), or **`(F)`** (full control) permissions.
- **Directories in the system `%PATH%`** that are writable (e.g., `C:\Windows\Temp`).
- **Sensitive locations** (e.g., `Program Files`, `Windows\System32`, `ProgramData`) with loose permissions.

**Example**:  
```cmd
icacls "C:\Program Files\VulnerableApp"
```
If the output includes `BUILTIN\Users:(M)` or `Everyone:(W)`, you can **modify files** in that directory.

---

### **2. Insecure Service Configurations**
Check services (`sc query`, `tasklist /svc`) for misconfigurations:  
**Key Indicators**:
- **Services running as `SYSTEM`** but with **writable executable paths** (e.g., `BINARY_PATH_NAME = C:\Vulnerable\service.exe`).
- **Unquoted service paths** with spaces (e.g., `C:\Program Files\App\service.exe`), which can allow hijacking via a writable parent directory.
- **Services referencing DLLs/scripts** in writable directories.

**Example**:  
If a service runs as `SYSTEM` with a path like `C:\Program Files\Bad App\app.exe`, and `C:\Program Files\Bad App` is writable, you can replace `app.exe` with a malicious binary.

---

### **3. Writable Paths**
Look for directories where you can **write files** or **plant executables**:  
**Key Targets**:
- **Temp directories**: `C:\Windows\Temp`, `C:\Users\Public\Temp`.
- **ProgramData**: `C:\ProgramData` (often has loose permissions).
- **Startup folders**: `C:\Users\<YourUser>\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup`.
- **Scheduled Task directories**: `C:\Windows\System32\Tasks` (if writable).

**Example**:  
If `C:\ProgramData` has `BUILTIN\Users:(F)`, you can plant a malicious script there and wait for a privileged process to execute it.

---

### **4. Autoruns and Scheduled Tasks**
Check for tasks or startup programs you can influence:  
**Key Indicators**:
- **Scheduled tasks** (`schtasks /query`) pointing to writable scripts/executables.
- **Autorun entries** (`reg query HKLM\...\Run`, `reg query HKCU\...\Run`) referencing writable paths.

**Example**:  
If a task runs `C:\Scripts\cleanup.bat` and you have write access to `C:\Scripts`, replace `cleanup.bat` with a reverse shell.

---

### **5. DLL Hijacking Opportunities**
Look for **missing DLLs** or **writable DLL paths** used by high-privileged processes:  
**Key Indicators**:
- **Process Monitor (ProcMon)** logs showing `NAME NOT FOUND` errors for DLLs.
- Services/processes loading DLLs from writable directories (e.g., `C:\Temp`).

**Example**:  
If a SYSTEM service tries to load `C:\BadApp\missing.dll` and `C:\BadApp` is writable, plant `missing.dll` to escalate privileges.

---

### **6. Insecure Registry Permissions**
Check for **writable registry keys** linked to services/software:  
**Key Indicators**:
- Use `reg query` and `icacls` (on registry hives) to see if you can modify keys like:
  - `HKLM\System\CurrentControlSet\Services\<ServiceName>` (service configurations).
  - `HKLM\Software\Microsoft\Windows\CurrentVersion\Run` (autoruns).

**Example**:  
If `HKLM\Software\SomeApp` has `Everyone:(F)`, you can modify registry entries to execute malicious code.

---

### **7. AlwaysInstallElevated**
Check if non-admin users can install MSI packages as admin:  
```cmd
reg query HKCU\Software\Policies\Microsoft\Windows\Installer /v AlwaysInstallElevated
reg query HKLM\Software\Policies\Microsoft\Windows\Installer /v AlwaysInstallElevated
```
If **both** return `0x1`, you can create a malicious MSI to gain SYSTEM privileges.

---

### **8. Unquoted Service Paths**
Find services with **unquoted paths** and spaces (e.g., `C:\Program Files\App\app.exe`):  
```cmd
wmic service get name,displayname,pathname,startmode | findstr /i "auto" | findstr /i /v "c:\windows\\" | findstr /i /v """
```
If a service path is unquoted and you have write access to a directory in the path (e.g., `C:\Program`), you can plant an executable named `Files\App\app.exe` to hijack execution.

---

### **Summary of Red Flags**
| **Vulnerability Type**       | **Command to Check**                                  | **Sign of Exploitability**                          |
|-------------------------------|-------------------------------------------------------|-----------------------------------------------------|
| Weak File Permissions         | `icacls "C:\Path"`                                    | Your user has `(W)`, `(M)`, or `(F)` permissions.   |
| Insecure Services             | `sc query` + `icacls` on service binary paths         | Service runs as SYSTEM with writable binary path.   |
| Writable Startup Locations    | `icacls "C:\Users\*\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"` | You can write to the folder. |
| Scheduled Tasks               | `schtasks /query /fo LIST`                            | Task action points to a writable script/executable. |
| AlwaysInstallElevated         | `reg query` for AlwaysInstallElevated                 | Both HKLM and HKCU keys are set to `1`.             |

---

### **Exploitation Workflow**
1. **Enumerate**: Use the commands above to gather data.  
2. **Identify**: Look for the red flags listed.  
3. **Verify**: Confirm write access with `icacls` or manual file creation (e.g., `echo test > target.txt`).  
4. **Exploit**: Replace files, write payloads, or abuse misconfigurations.  

Focus on **combining SeChangeNotifyPrivilege** (to bypass traversal checks) with weak permissions in restricted directories (e.g., `Program Files`, `Windows\System32`).


#>