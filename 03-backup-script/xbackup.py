#!/usr/bin/env python3
import os
import subprocess
import argparse
import shutil
import datetime

def rename_old_backups(backup_dir, folder_prefix):
    all_backups = os.listdir(backup_dir)
    backups_to_rename = [backup for backup in all_backups if backup.startswith(folder_prefix)]
    backups_to_rename.sort(reverse=True)
    if backups_to_rename:
        for backup in backups_to_rename[1:]:
            if not backup.endswith("Old"):
                old_backup_path = os.path.join(backup_dir, backup)
                new_backup_path = os.path.join(backup_dir, f"{backup}Old")
                if os.path.exists(new_backup_path):
                    shutil.rmtree(new_backup_path)  # Use shutil.rmtree to delete non-empty directories
                os.rename(old_backup_path, new_backup_path)
    else:
        return None
  
def run_command(command):
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
    stdout, stderr = process.communicate()
    return stdout.decode('utf-8'), stderr.decode('utf-8'), process.returncode

def create_backup(source_dir, backup_dir, user, server, debug, full_backup):
    backup_type = "Full" if full_backup else "Inc"
    rsync_command = f"rsync -avz"
    now = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    if debug:
        rsync_command += " --debug=all1"
    if full_backup:
        backup_filename = f"FullBackup_{now}"
        rsync_command += f" {user}@{server}:{source_dir}/ {backup_dir}/{backup_filename}/"
    else:
        full_backup_dirs = sorted(os.listdir(backup_dir), reverse=True)
        most_recent_full_backup = None
        for backup_subdir in full_backup_dirs:
            if backup_subdir.startswith("FullBackup"):
                most_recent_full_backup = os.path.abspath(os.path.join(backup_dir, backup_subdir))
                break

        if most_recent_full_backup is not None:
            backup_filename = f"IncBackup_{now}"
            rsync_command += f" --link-dest={most_recent_full_backup}/ {user}@{server}:{source_dir}/ {backup_dir}/{backup_filename}/"
        else:
            backup_filename = f"FullBackup_{now}"
            print("No full backup found. Performing a full backup instead.")
            backup_type = "Full"
            rsync_command += f"  {user}@{server}:{source_dir}/ {backup_dir}/{backup_filename}/"

    os.makedirs(f"{backup_dir}/{backup_filename}", exist_ok=True)
    print(f"Creating {backup_type} Backup...")
        
    stdout, stderr, returncode = run_command(rsync_command)

    if returncode == 0:
        print(f"Backup successful.")
        rename_old_backups(backup_dir, backup_type)


    else:
        print(f"Error occurred during {backup_type} Backup.")
        print("Error message:")
        print(stderr)

def main():
    parser = argparse.ArgumentParser(description='Backup script')
    parser.add_argument('source_dir', help='Source directory to backup')
    parser.add_argument('backup_dir', help='Directory to store backups')
    parser.add_argument('--user', help='SSH user for remote server', required=True)
    parser.add_argument('--server', help='IP address of the remote server', required=True)
    parser.add_argument('--debug', action='store_true', help='Enable debug mode')
    parser.add_argument('--full', action='store_true', help='Perform a full backup')
    parser.add_argument('--inc', action='store_true', help='Perform an incremental backup')

    args = parser.parse_args()

    if not args.full and not args.inc:
        parser.error('Please specify either --full or --inc to perform a backup.')

    if args.full and args.inc:
        parser.error('Please specify only one of --full or --inc for the backup type.')

    create_backup(args.source_dir, args.backup_dir, args.user, args.server, args.debug, args.full)

if __name__ == '__main__':
    main()