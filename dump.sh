#!/bin/bash

############################################
# TEAMS CONFIG
############################################
TEAMS_WEBHOOK_URL="https://barath.webhook.office.com/webhookb2/0a7e1a0a-d77b-4044-9437-bba6366c4655@c4144943-d4ea-417f-9e..."
HOSTNAME=$(hostname)
JOB_NAME="MySQL K8s Backup of Barathg-Environment's"

############################################
# LOGGING
############################################
timestamp=$(date +%F_%H-%M)
LOG_FILE="/root/mysql-backup-logs/mysql-backup-$timestamp.log"
exec >> "$LOG_FILE" 2>&1

############################################
# FUNCTIONS
############################################
send_teams_message() {
    local MESSAGE="$1"

    curl -s -H "Content-Type: application/json" -d "{
        \"@type\": \"MessageCard\",
        \"@context\": \"http://schema.org/extensions\",
        \"summary\": \"$JOB_NAME\",
        \"themeColor\": \"0076D7\",
        \"title\": \"$JOB_NAME\",
        \"text\": \"$MESSAGE\"
    }" "$TEAMS_WEBHOOK_URL" > /dev/null
}

send_teams_log() {
    LOG_CONTENT=$(tail -n 40 "$LOG_FILE" | sed 's/"/\\"/g')

    curl -s -H "Content-Type: application/json" -d "{
        \"@type\": \"MessageCard\",
        \"@context\": \"http://schema.org/extensions\",
        \"summary\": \"$JOB_NAME Logs\",
        \"themeColor\": \"FFA500\",
        \"title\": \"📄 Backup Log (Last 40 lines)\",
        \"text\": \"\`\`\`\n$LOG_CONTENT\n\`\`\`\"
    }" "$TEAMS_WEBHOOK_URL" > /dev/null
}

############################################
# START ALERT
############################################
send_teams_message "🚀 **Backup STARTED**  
**Host:** $HOSTNAME  
**Time:** $(date)"

echo "--- MySQL Backup started at $(date) ---"

############################################
# BACKUP CONFIG
############################################
DATE=$(date +%F-%H-%M)
TMP_DIR="/tmp/mysql-backups/$DATE"
REMOTE_DIR="/home/devops/mysql-backups/$DATE"
mkdir -p "$TMP_DIR"

############################################
# MYSQL PASSWORD
############################################
MYSQL_ROOT_PASS=$(kubectl get secret mysql-root-secret -n data-sit -o jsonpath="{.data.root-password}" | base64 -d)

############################################
# BACKUPS
############################################
echo "🔄 Backing up Env-1..."
kubectl exec -n data-sit deploy/mysql-Env-1 -- \
  mysqldump -uroot -p"$MYSQL_ROOT_PASS" --all-databases --routines --events --triggers > "$TMP_DIR/Env-1.sql"

echo "🔄 Backing up Env-2..."
kubectl exec -n data-sit deploy/mysql-Env-2 -- \
  mysqldump -uroot -p"$MYSQL_ROOT_PASS" --all-databases --routines --events --triggers --single-transaction --force > "$TMP_DIR/Env-2.sql"

echo "🔄 Backing up Env-3..."
kubectl exec -n data-sit mysql-Env-3-0 -- \
  mysqldump -uroot -p"$MYSQL_ROOT_PASS" --all-databases --routines --events --triggers --single-transaction --force > "$TMP_DIR/Env-3.sql"

echo "🔄 Backing up Env-4-ssl..."
kubectl exec -n data-sit deploy/Env-4-ssl -- \
  mysqldump -uroot -p"$MYSQL_ROOT_PASS" --all-databases --routines --events --triggers > "$TMP_DIR/Env-4.sql"

echo "🔄 Backing up Env-5..."
kubectl exec -n data-sit deploy/mysql-Env-5 -- \
  mysqldump -uroot -p"$MYSQL_ROOT_PASS" --all-databases --routines --events --triggers > "$TMP_DIR/Env-5.sql"

echo "🔄 Backing up Env-6..."
kubectl exec -n data-sit deploy/Env-6-mysql -- \
  mysqldump -uroot -p"$MYSQL_ROOT_PASS" --all-databases --routines --events --triggers > "$TMP_DIR/Env-6.sql"
  

############################################
# COPY TO Barath-Dump-str-server
############################################
echo "📦 Sending to Barath-Dump-str-server..."
ssh -p 22 devops@0.0.0.0 "mkdir -p $REMOTE_DIR"
scp -P 22 "$TMP_DIR"/*.sql devops@0.0.0.0:"$REMOTE_DIR/"

############################################
# STATUS + CLEANUP
############################################
if [ $? -eq 0 ]; then
    echo "✅ Backup completed and copied to Barath-Dump-str-server at: $REMOTE_DIR"

    echo "🧹 Cleaning up old backups on Barath-Dump-str-server (older than 5 days)..."
    ssh -p 22 devops@0.0.0.0 \
      'find /home/devops/mysql-backups/ -type d -mtime +5 -exec rm -rf {} \;'

    BACKUP_STATUS="SUCCESS"
else
    echo "❌ Backup FAILED! Check connection or path."
    BACKUP_STATUS="FAILED"
fi

############################################
# END ALERT + LOG
############################################
send_teams_message "✅ **Backup $BACKUP_STATUS**  
**Host:** $HOSTNAME  
**Time:** $(date)  
**Destination:** (Host:Barath-Dump-str-server) at $REMOTE_DIR"

send_teams_log

echo "--- MySQL Backup finished at $(date) ---"
