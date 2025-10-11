# 🐍 Python Package Installation Issues - Solutions

## Problem: "cannot uninstall blinker - package was installed by debian"

This error occurs when trying to uninstall or upgrade Python packages that are managed by the system package manager (`apt`/`dpkg`) instead of `pip`.

---

## ✅ **Solution 1: Use Virtual Environment (Recommended)**

Virtual environments isolate your project dependencies from system packages.

### Quick Setup

```bash
# Install venv
sudo apt install python3-venv

# Create virtual environment
cd /opt/platebridge
python3 -m venv venv

# Activate it
source venv/bin/activate

# Install dependencies (no conflicts!)
pip install -r requirements.txt

# Run your POD agent
python agent.py

# Deactivate when done
deactivate
```

### For Systemd Service

Update your service file to use the venv:

```bash
sudo nano /etc/systemd/system/platebridge-pod.service
```

```ini
[Unit]
Description=PlateBridge POD Agent
After=network.target

[Service]
Type=simple
User=platebridge
WorkingDirectory=/opt/platebridge
Environment="PATH=/opt/platebridge/venv/bin"
ExecStart=/opt/platebridge/venv/bin/python agent.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl restart platebridge-pod
```

---

## ✅ **Solution 2: Our Updated Setup Script**

The `setup.sh` script has been updated to automatically create and use a virtual environment:

```bash
cd /path/to/platebridge/pod-agent
sudo ./setup.sh
```

**What it does:**
- ✅ Checks for `python3-venv`
- ✅ Creates isolated virtual environment
- ✅ Installs all dependencies safely
- ✅ Configures systemd to use venv
- ✅ No system package conflicts!

---

## ⚠️ **Solution 3: --break-system-packages (Not Recommended)**

**Only use if you understand the risks:**

```bash
pip install --break-system-packages -r requirements.txt
```

**Why this is risky:**
- Can break system tools that depend on specific package versions
- System updates may cause conflicts
- Hard to troubleshoot when things break
- Not portable across systems

---

## 🔍 **Understanding the Issue**

### System vs User Packages

**System packages (apt):**
```bash
sudo apt install python3-flask
# Installs to: /usr/lib/python3/dist-packages/
# Managed by: dpkg/apt
# Used by: System tools
```

**User packages (pip):**
```bash
pip install flask
# Installs to: ~/.local/lib/python3.X/site-packages/
# Managed by: pip
# Used by: Your projects
```

**Virtual environment (venv):**
```bash
python3 -m venv myenv
source myenv/bin/activate
pip install flask
# Installs to: ./myenv/lib/python3.X/site-packages/
# Managed by: pip (isolated)
# Used by: Only this project
```

### Why Debian Packages Exist

Some Python packages are installed by Debian because:
- System tools depend on them
- They're tested for compatibility
- They receive security updates
- Examples: `python3-requests`, `python3-flask`, `python3-blinker`

---

## 🛠️ **Fixing Existing Installation**

### If You Already Installed Without Venv

**Move to virtual environment:**

```bash
# Go to POD directory
cd /opt/platebridge

# Create venv
python3 -m venv venv

# Activate
source venv/bin/activate

# Install requirements
pip install -r requirements.txt

# Update systemd service
sudo nano /etc/systemd/system/platebridge-pod.service
# Change ExecStart to: /opt/platebridge/venv/bin/python agent.py

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart platebridge-pod
```

---

## 🧪 **Verify Your Setup**

### Check if Using Venv

```bash
# Should show venv path
which python
# Output: /opt/platebridge/venv/bin/python

# Should show venv in path
echo $VIRTUAL_ENV
# Output: /opt/platebridge/venv
```

### Check Package Location

```bash
# Activate venv
source /opt/platebridge/venv/bin/activate

# Check where packages are installed
python -c "import flask; print(flask.__file__)"
# Should show: /opt/platebridge/venv/lib/python3.X/site-packages/flask/__init__.py

# List installed packages
pip list
```

### Test POD Agent

```bash
cd /opt/platebridge
source venv/bin/activate
python agent.py
```

---

## 📊 **Comparison: System vs Venv**

| Aspect | System Install | Virtual Environment |
|--------|----------------|---------------------|
| **Command** | `sudo pip install` | `pip install` (in venv) |
| **Location** | `/usr/lib/python3/dist-packages/` | `./venv/lib/python3.X/site-packages/` |
| **Conflicts** | ⚠️ Can break system | ✅ Isolated |
| **Portability** | ❌ System-specific | ✅ Easy to replicate |
| **Permissions** | Needs sudo | No sudo needed |
| **Updates** | System managed | You control |
| **Best For** | System tools | Applications |

---

## 🚀 **Quick Reference Commands**

### Create and Use Venv

```bash
# Create
python3 -m venv venv

# Activate (Linux/Mac)
source venv/bin/activate

# Activate (Windows)
venv\Scripts\activate

# Install packages
pip install package-name

# Deactivate
deactivate
```

### Manage Dependencies

```bash
# Save current packages
pip freeze > requirements.txt

# Install from file
pip install -r requirements.txt

# Upgrade all packages
pip list --outdated
pip install --upgrade package-name
```

### Clean Reinstall

```bash
# Remove venv
rm -rf venv

# Create fresh venv
python3 -m venv venv
source venv/bin/activate

# Install clean
pip install -r requirements.txt
```

---

## 📁 **Directory Structure**

**With virtual environment:**
```
/opt/platebridge/
├── venv/                    ← Virtual environment
│   ├── bin/
│   │   ├── python          ← Use this Python
│   │   ├── pip             ← Use this pip
│   │   └── activate        ← Source this
│   ├── lib/
│   │   └── python3.X/
│   │       └── site-packages/  ← Packages install here
│   └── ...
├── agent.py
├── requirements.txt
├── config.yaml
└── ...
```

---

## ❓ **Common Questions**

### Q: Do I need to activate venv every time?

**A:** Not if using systemd service. The service file points directly to `/opt/platebridge/venv/bin/python`.

For manual runs: Yes, activate first.

### Q: Can I use the same venv for multiple projects?

**A:** No, create separate venvs for each project to avoid dependency conflicts.

### Q: What if I forget to activate venv?

**A:** You'll use system Python and may get "module not found" errors or version conflicts.

### Q: How much disk space does venv use?

**A:** Usually 50-200 MB depending on packages. Minimal compared to system package conflicts!

### Q: Can I move venv to another location?

**A:** Not easily. Better to create new venv at destination and reinstall packages.

---

## 🔧 **Troubleshooting**

### "No module named 'venv'"

```bash
sudo apt update
sudo apt install python3-venv
```

### "pip: command not found" (inside venv)

```bash
# Venv should include pip, but if missing:
python -m ensurepip --upgrade
```

### "Permission denied" when activating

```bash
chmod +x venv/bin/activate
source venv/bin/activate
```

### Packages not found after installing

```bash
# Make sure venv is activated
which python
# Should show: /path/to/venv/bin/python

# If not:
source venv/bin/activate
```

### Service won't start with venv

```bash
# Check service file
sudo systemctl cat platebridge-pod

# Verify paths
ls -la /opt/platebridge/venv/bin/python

# Check service logs
sudo journalctl -u platebridge-pod -n 50
```

---

## ✅ **Best Practices**

1. **Always use virtual environments** for Python applications
2. **Never use `sudo pip install`** unless you know exactly why
3. **Keep `requirements.txt` updated** with `pip freeze > requirements.txt`
4. **Test in venv before deploying** to catch dependency issues early
5. **Document venv creation** in your setup/deployment docs
6. **Use absolute paths** in systemd service files
7. **Activate venv before running** manual commands

---

## 📚 **Additional Resources**

- Python venv docs: https://docs.python.org/3/library/venv.html
- pip user guide: https://pip.pypa.io/en/stable/user_guide/
- PEP 405 (venv spec): https://www.python.org/dev/peps/pep-0405/

---

## 🎯 **TL;DR - Quick Fix**

```bash
# The fix (30 seconds):
cd /opt/platebridge
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Update systemd:
sudo nano /etc/systemd/system/platebridge-pod.service
# Change ExecStart to: /opt/platebridge/venv/bin/python agent.py
sudo systemctl daemon-reload
sudo systemctl restart platebridge-pod

# Done! ✅
```

**Our updated `setup.sh` does all of this automatically!**
