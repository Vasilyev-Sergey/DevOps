# Скрипт бекапа который:

1. Соединяется с другим сервером и копирует данные. Копирование происходит в зашифрованном, сжатом виде.
2. Есть возможность изменять некоторые параметры при запуске скрипта:
* Директория для хранения бэкапов
* Пользователь
* Cервер с которым происходит соединение (указывается IP)
* Есть возможность запуска скрипта в debug режиме
* Изменение директорий, которые копируются с удаленного сервера
* Возможность выполнения full и incremental backup
* Для ознакомления с имеющимися настройками, использовать ключ -h при запуске.
3. Для ротации устаревших версий используется logrotate. Логика работы: для full backup создается 2 папки (аналогично и для
   incremental):
* Full (Inc) - сохраняется последний backup
* FullOld (IncOld) - последние backup, именно эта файлы и ротируются.

xbackup.py -h
usage: xbackup.py [-h] --user USER --server SERVER [--debug] [--full] [--inc] source_dir backup_dir

Backup script

positional arguments:
  source_dir       Source directory to backup
  backup_dir       Directory to store backups

optional arguments:
  -h, --help       show this help message and exit
  --user USER      SSH user for remote server
  --server SERVER  IP address of the remote server
  --debug          Enable debug mode
  --full           Perform a full backup
  --inc            Perform an incremental backup