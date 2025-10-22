# Deployment Script - Simple Guide

> **What this does:** Automates setup, deployment, and configuration of Dockerized applications on remote Linux servers with comprehensive error handling, logging, and validation.

## 🚀 Quick Start (5 Minutes)

### What You Need

1. **A server** (Ubuntu Linux recommended)

   - AWS, DigitalOcean, Linode, etc.
   - You need: username, IP address, SSH access

2. **Your code on GitHub**

   - Must have a `Dockerfile` in the root folder

3. **GitHub Token**
   - Go to: GitHub → Settings → Developer Settings → Personal Access Tokens
   - Create token with `repo` access
   - Copy and save it

---

## 📥 Installation

```bash
# Download the script
wget https://github.com/PreciousEzeigbo/hng13-stage1-devops/deploy.sh

# Make it runnable
chmod +x deploy.sh
```

---

## ▶️ How to Use

### Step 1: Run the Script

```bash
./deploy.sh
```

### Step 2: Answer These Questions

| Question              | Example Answer                      | Where to Find It                   |
| --------------------- | ----------------------------------- | ---------------------------------- |
| Git Repository URL    | `https://github.com/user/myapp.git` | GitHub repo (green "Code" button)  |
| Personal Access Token | `ghp_xxxxxxxxxxxx`                  | GitHub Settings (you created this) |
| Branch name           | `main`                              | Just press Enter for default       |
| SSH username          | `ubuntu`                            | Your server provider tells you     |
| Server IP address     | `192.168.1.100`                     | Your server dashboard              |
| SSH key path          | `~/.ssh/id_rsa`                     | Just press Enter for default       |
| Application port      | `3000`                              | Check your app code                |

### Step 3: Wait for Success

```
[SUCCESS] DEPLOYMENT COMPLETED SUCCESSFULLY!
Application URL: http://192.168.1.100
```

### Step 4: Visit Your App

Open browser: `http://YOUR-SERVER-IP`

---

## 🔑 First Time Setup

### Create SSH Key (One Time Only)

```bash
# Generate key
ssh-keygen -t rsa -b 4096

# Press Enter 3 times (use defaults)

# Copy to server (replace with your details)
ssh-copy-id your-username@your-server-ip
```

Test it works:

```bash
ssh your-username@your-server-ip
# Should login without password
# Type 'exit' to logout
```

---

## 🔧 Common Issues

### "Permission denied"

```bash
chmod +x deploy.sh
```

### "SSH connection failed"

- Check username and IP are correct
- Make sure you ran `ssh-copy-id` first
- Try: `ssh your-username@your-server-ip` manually

### "No Dockerfile found"

- Add a `Dockerfile` to your GitHub repo root
- Use examples above

### "Cannot clone repository"

- Check GitHub URL is correct
- Check your Personal Access Token is valid
- Make sure token has `repo` permissions

---

## 🧹 Remove Everything

```bash
./deploy.sh --cleanup
```

This removes:

- Docker containers
- Docker images
- Nginx configuration
- Deployed files

---

## 📖 What Happens When You Run It?

```
1. Downloads your code from GitHub
2. Connects to your server
3. Installs Docker and Nginx (if needed)
4. Copies your code to server
5. Builds Docker image
6. Runs your app in a container
7. Sets up Nginx to forward traffic
8. Your app is live! 🎉
```

---

## 💡 Examples

### Deploy Node.js App

```bash
./deploy.sh

# When asked:
# Repo: https://github.com/yourname/nodejs-app.git
# Port: 3000
```

### Deploy Python Flask App

```bash
./deploy.sh

# When asked:
# Repo: https://github.com/yourname/flask-app.git
# Port: 5000
```

---

## 📊 Check Status

```bash
# SSH into your server
ssh username@server-ip

# See running containers
docker ps

# View app logs
docker logs your-app-name

# Restart app
docker restart your-app-name
```

---

## 🆘 Need Help?

### Check Logs

```bash
cat logs/deploy_*.log
```

### Test Each Step Manually

1. **Can you SSH?**

   ```bash
   ssh username@server-ip
   ```

2. **Can you clone the repo?**

   ```bash
   git clone https://github.com/user/repo.git
   ```

3. **Does your Dockerfile exist?**
   ```bash
   ls -la Dockerfile
   ```

---

## ✅ Checklist Before Running

- [ ] I have a Linux server
- [ ] I can SSH into my server
- [ ] My code is on GitHub
- [ ] I have a Dockerfile in my repo
- [ ] I created a GitHub Personal Access Token
- [ ] I know my app's port number

---

## 🎯 Success Looks Like This

```bash
$ ./deploy.sh

==========================================
  Docker Deployment Automation Script
==========================================

Enter Git Repository URL: https://github.com/john/myapp.git
Enter Personal Access Token: ****
Enter branch name (default: main):
Enter SSH username: ubuntu
Enter server IP address: 192.168.1.100
Enter SSH key path: ~/.ssh/id_rsa
Enter application internal port: 3000

[INFO] Cloning repository...
[SUCCESS] Repository cloned
[INFO] Connecting to server...
[SUCCESS] Connected
[INFO] Installing Docker...
[SUCCESS] Docker installed
[INFO] Deploying application...
[SUCCESS] Application deployed
[INFO] Configuring Nginx...
[SUCCESS] Nginx configured

==========================================
  DEPLOYMENT COMPLETED SUCCESSFULLY!
==========================================
Application URL: http://192.168.1.100
```

---

## 📞 Support

**Before asking for help:**

1. Read the error message
2. Check the log file in `logs/` folder
3. Try the troubleshooting steps above

---

## 🔒 Security Notes

- Your GitHub token is never saved
- Uses SSH keys (more secure than passwords)
- All inputs are validated
- Logs don't contain sensitive data

---

**That's it! You're ready to deploy.** 🚀

Run `./deploy.sh` and answer the questions!
