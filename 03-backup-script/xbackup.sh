#!/bin/bash

# Параметры по умолчанию
BACKUP_DIR="/path/to/backup/directory"
USER="remote_user"
REMOTE_SERVER="remote_server_ip"
DEBUG_MODE=false
COPY_DIRECTORIES=("dir1" "dir2")  # Директории, которые копируются с удаленного сервера
BACKUP_TYPE="incremental"  # Тип бекапа по умолчанию (допустимые значения: full или incremental)

# Парсинг аргументов командной строки с помощью getopts
while getopts "dhf:i:u:s:" opt; do
    case $opt in
        d)
            DEBUG_MODE=true
            ;;
        h)
            show_help
            exit 0
            ;;
        f)
            BACKUP_TYPE="full"
            ;;
        i)
            BACKUP_TYPE="incremental"
            ;;
        u)
            USER="$OPTARG"
            ;;
        s)
            REMOTE_SERVER="$OPTARG"
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            show_help
            exit 1
            ;;
    esac
done

# Вывод справки
function show_help() {
    echo "Usage: $0 [-d] [-f|-i] [-u user] [-s server_ip] [-h]"
    echo "Options:"
    echo "  -d            Enable debug mode"
    echo "  -f            Perform full backup"
    echo "  -i            Perform incremental backup (default)"
    echo "  -u user       Specify the remote user (default: remote_user)"
    echo "  -s server_ip  Specify the remote server IP (default: remote_server_ip)"
    echo "  -h            Show this help message"
}

# Отображение параметров, если включен debug режим
if $DEBUG_MODE; then
    echo "DEBUG MODE: Enabled"
    echo "Backup Type: $BACKUP_TYPE"
    echo "User: $USER"
    echo "Remote Server IP: $REMOTE_SERVER"
fi

# Здесь добавляется логика для копирования различных директорий, если требуется
# Например, для полного бекапа можно изменить директории для копирования следующим образом:
if [ "$BACKUP_TYPE" == "full" ]; then
    COPY_DIRECTORIES=("dir3" "dir4")  # Изменить на необходимые директории для полного бекапа
fi

# Команда для копирования с помощью rsync через ssh
# Параметры:
# -a: Архивный режим (включает рекурсивное копирование, сохранение прав доступа и времени модификации)
# -z: Сжатие данных при передаче
# -e: Указание программы для подключения (в данном случае ssh)
# --delete: Удаление файлов на приемной стороне, которых нет на отправной
# --exclude: Исключение указанных директорий из копирования
# При копировании на удаленный сервер используем формат "user@server:/remote/directory/"
rsync -az --delete --exclude={".git","node_modules"} -e ssh "$USER@$REMOTE_SERVER:/path/to/remote/directory/" "$BACKUP_DIR"

# Ротация устаревших версий с помощью logrotate
logrotate -s "$BACKUP_DIR/logrotate_status" -f /path/to/logrotate.conf

exit 0


#!/bin/bash

# ...

# Directory for full backups
FULL_BACKUP_DIR="$BACKUP_DIR/Full"
# Directory for incremental backups
INCREMENTAL_BACKUP_DIR="$BACKUP_DIR/Incremental"
# Directory to store the latest backup (symlink)
LATEST_BACKUP_DIR="$BACKUP_DIR/Latest"

# ...

# If performing incremental backup, set the source directory to the previous full or incremental backup
if [ "$BACKUP_TYPE" == "incremental" ]; then
    # Get the most recent full or incremental backup
    PREVIOUS_BACKUP=$(find "$FULL_BACKUP_DIR" "$INCREMENTAL_BACKUP_DIR" -maxdepth 1 -type d -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2)

    # Use the --link-dest option to link unchanged files to the previous backup
    LINK_DEST="--link-dest=$PREVIOUS_BACKUP"
fi

# Perform the backup using rsync with the appropriate options
rsync -az $LINK_DEST --delete --exclude={".git","node_modules"} -e ssh "$USER@$REMOTE_SERVER:/path/to/remote/directory/" "$INCREMENTAL_BACKUP_DIR"

# Update the symlink to the latest backup directory
rm -f "$LATEST_BACKUP_DIR" && ln -s "$INCREMENTAL_BACKUP_DIR" "$LATEST_BACKUP_DIR"

# ...


#!/bin/sh

# This script does personal backups to a rsync backup server. You will end up
# with a 7 day rotating incremental backup. The incrementals will go
# into subdirectories named after the day of the week, and the current
# full backup goes into a directory called "current"
# tridge@linuxcare.com

# directory to backup
BDIR=/home/$USER

# excludes file - this contains a wildcard pattern per line of files to exclude
EXCLUDES=$HOME/cron/excludes

# the name of the backup machine
BSERVER=owl

# your password on the backup server
export RSYNC_PASSWORD=XXXXXX

########################################################################

BACKUPDIR=`date +%A`
OPTS="--force --ignore-errors --delete-excluded --exclude-from=$EXCLUDES 
      --delete --backup --backup-dir=/$BACKUPDIR -a"

export PATH=$PATH:/bin:/usr/bin:/usr/local/bin

# the following line clears the last weeks incremental directory
[ -d $HOME/emptydir ] || mkdir $HOME/emptydir
rsync --delete -a $HOME/emptydir/ $BSERVER::$USER/$BACKUPDIR/
rmdir $HOME/emptydir

# now the actual transfer
rsync $OPTS $BDIR $BSERVER::$USER/current


//////////////////////

#!/bin/bash
# Копирует файлы в формате [from]/*/%Y%m%d/%H%M/* или [from]/*/%Y%m%d/* в s3 хранилище либо через rsync на хост
# Преимущества скрипта перед обычным копированием в том что можно задать интервал поминутно или по дням для копирования
# и за счет заранее определенной структуре директорий с временем в пути скрипт не обходит все файлы с проверкой mtime и т.д.
# что в итоге позволяет не тормозить при большом количестве файлов.
# так же помимо проверок md5 самой утилитой aws s3 sync, сохраняется лок файл успешных папок которые уже копировались с проверкой md5
# что в итоге позволяет мгновенно отфильтровывать папки которые уже были скопированны и запускать скрипт на большом интервале времени в истории
# на регулярной основе чтобы докопировать в s3 все папки которые по какой-то причине не были скопированны заранее.
#
# когда скрипт запускается на интервале по дням, он хранит отдельный лог файл, чтобы повторно проверить md5 суммы файлов,
# которые копировались поминутно. При каждая единица копирования aws s3 sync все равно происходит поминутно, так как
# s3 плохо заточен на листинг файлов и при синке всех файлов сразу за день он может отвалится по таймауту при листинге файлов
# при этом чтобы не было простоев между запусками этих минутных копирований делается по 4 копирования в паралель
# (больше делать смысла нет, так как aws s3 sync и так копирует в несколько потоков и единственная цель избежать простоя на листинг и между запусками)
# логи обычно храняться в /var/log/s3backup если запущенно через папет
# лок файл хранится в /var/lib/s3backup
#
# сейчас в локе хранится хеш только названия папки, хотя можно сделать хеш от списка всех файлов их mtime или md5
#  но если прогонять за большой интервал времени то это очень медленно так как это надо считать каждый раз
# так же тэг лока имеет префикс даты чтобы префикс приложения не влиял на сортировку и вставка была в конец файла
# и имеет постфикс название папки чтобы было лучше понимание какая папка копировалась при просмотре лок файла глазами
# по сути хеш проверяет название папки mtime и косвенно количество подпапок по размеру этой папки на fs (это не du)
# но больше оставлен для универсальности если в будущем изменится алгоритм расчета хеша и будет что-то еще
#
# если удалить лок файл то при повторном запуске будет опять на все файлы проверка md5 хеш сумм что может занять время,
#  но не критично в глобальном смысле так как не будут перекопироваться все файлы.
# если по какой-то причине синк папки отвалится то не будет записанно в лок файл строчка об успехе, что приведет к тому что
#  при повторном регулярном запуске эта папка будет обработанна повторно.
set -e
from="/home/filestorage/" # исходные файлы для бэкапа
mode="s3"

export LC_ALL=C
export LC_COLLATE=C

rsync_host="filestorage@bigstorage1-backup.srg-it.ru",
rsync_port="58319",
rsync_path="/home/filestorage/",

s3_bucket="s3://filestorage/"      # бакет плюс путь внутри бакета куда копировать
s3_endpoint="https://s3.srg-it.ru" # эндпоинт s3 за котором лежат бакеты в которые копировать

# опция для команды seq будут перебираться папки с этой последовательностью времени вычтенной из текущего времени в единицах unit
# для минут лучш минут лучше запускать не позднее чем 2 минуты назад, так как не все файлы могли успеть записаться
#  и будет некорректно сохранено в лок файл что эта минута успешно скопированна
#  тогда файл будет забэкаплен только при повторном проходе по дням.
# например чтобы идти от последних файлов к более старым можно передать -2 -1 -4, что равносильно round(now() -2 -3 -4 unit, unit)
# от шаг до
seq="-3 1 -2"

# перебирать папки по минутно либо по дням, для того и другого используется отдельный lock файл что уже скопировалось
unit="min"                # | day # пока другие интервалы не поддерживаются так как есть своя спицифика на каждый и нет большого смысла
export TZ='Europe/Moscow' # чтобы не было сюрпризов с датами из-за разных таймзон

# при изменении алгоритма хеширования можно изменить версию чтобы не попортить старый лок файл
doneVersion="v1"

removeSourceFiles="" # "true" for delete

while [[ "$#" -gt 0 ]]; do
  case $1 in
  -f | --from)
    from="$2"
    shift
    ;;
  -m | --mode)
    mode="$2"
    shift
    ;;
  -h | --rsync_host)
    rsync_host="$2"
    shift
    ;;
  -p | --rsync_port)
    rsync_port="$2"
    shift
    ;;
  -P | --rsync_path)
    rsync_path="$2"
    shift
    ;;
  -b | --s3_bucket)
    s3_bucket="$2"
    shift
    ;;
  -e | --s3_endpoint)
    s3_endpoint="$2"
    shift
    ;;
  -s | --seq)
    seq="$2"
    shift
    ;;
  -u | --unit)
    unit="$2"
    shift
    ;;
  --removeSourceFiles)
    removeSourceFiles="$2"
    shift
    ;;
  -v | --version)
      doneVersion="$2"
      shift
      ;;
  *)
    echo "Unknown parameter passed: $1"
    exit 1
    ;;
  esac
  shift
done


if [[ $removeSourceFiles == "true" ]]; then
  doneVersion="${doneVersion}Del"
fi

# путь до лок файла
doneFile="/var/lib/s3backup/$unit.$mode.done.$doneVersion.log"
mkdir -p /var/lib/s3backup/
touch "$doneFile"

#sshCmd="ssh -i $HOME/.ssh/backup.key -o StrictHostKeyChecking=no -p $rsync_port"
sshCmd="ssh -i $HOME/.ssh/id_ed25519  -o Compression=no -x -T -c aes128-gcm@openssh.com -o StrictHostKeyChecking=no -p $rsync_port"


# gnu parallel может спамить в лог что надо задонатить, этот файл отключает этот спам
mkdir -p "$HOME/.parallel/"
touch "$HOME/.parallel/will-cite"

echo $(date -Iseconds) s3backup "seq $seq $unit" "from '$from' to '$s3_endpoint' '$s3_bucket'"
cd "$from"

# все возможные единицы времени для проверки на наличие файлов (округленное до unit)
dates=()
for offset in $(seq $seq); do
  if [[ $unit == "min" ]]; then
    dates+=($(date '+%Y%m%d/%H%M' --date "now $offset min"))
  elif [[ $unit == "day" ]]; then
    dates+=($(date '+%Y%m%d' --date "09:00 now $offset day"))
  fi
done

# тэги по всем найденным папкам, для дальнейшей фильтрации от уже скопированных
declare -A tagsMap
initialTags=()
for dateX in "${dates[@]}"; do
  # поиск всех папок под любым префиксом на конкретную дату
  dirsX=($(find *"/$dateX/" -maxdepth 0 -type d 2>/dev/null || true))

  for dir in "${dirsX[@]}"; do
    # вычисление тэга в лок файл для каждой папки

    # too slow
    # hash=$(find "$from$dir" -type f -printf "%T@ %s %P\n" | sort -u | md5sum | awk '{ print $1 }')
    hash=$(find "$from$dir" -maxdepth 0 -type d -printf "%T@ %s %P\n" | sort -u | md5sum | awk '{ print $1 }')
    tag="$dateX-$hash-$dir" # $dateX- чтобы была лучше сортировка, -$dir для наглядности
    tagsMap["$tag"]="$dir"  # в дальнейшем чтобы доставать папки которые не были найденны в lock файле

    initialTags+=("$tag") # список чтобы сохранить порядок копирования
  done
done

# comm работает только с сортированными файлами
# пришлось создать временный файл так как при запуске через cron при передаче команде через flock -с 'echo -e tagsMap | comm - donefile'
#  если делать echo -e $tagsString он по какой-то причине логирует -e, а при обычном запуске без крона все ок
tmpfile=$(mktemp /tmp/s3backup.XXXXXX)
printf '%s\n' "${initialTags[@]}" | sort -u >$tmpfile
# тэги которые уже скопированны, чтобы исключить их из обработки
flock -w 3600 "$doneFile" -c "sort -u -o $doneFile $doneFile"
doneTags=($(flock -w 3600 $doneFile comm -12 $tmpfile $doneFile))
rm $tmpfile

# удаляем тэги которые уже скопированны
for doneTag in ${doneTags[@]}; do
  unset tagsMap[$doneTag]
done
unset doneTags

# лист только с теми тэгами которые нужно копировать с сохранением исходного порядка
tagsToCopy=()
for tag in ${initialTags[@]}; do
  if [[ ${tagsMap[$tag]} ]]; then
    tagsToCopy+=($tag)
  fi
done
unset initialTags

# не идем дальше если все тэги и так уже найденны в lock файле
if [[ ${#tagsToCopy[@]} == 0 ]]; then
  echo $(date -Iseconds) nothing to backup
  exit 0
fi

echo $(date -Iseconds) ${#tagsToCopy[@]} $unit $mode dirs backup START

# собственно перебираем тэги которые не были найденны в lock файле и синкаем соответствующую папку
for tag in "${tagsToCopy[@]}"; do
  dir=${tagsMap[$tag]}

  # лог для бОльшей прозрачности процесса
  count=$(find "$from$dir" -type f | wc -l)
  du=$(du -h -d 0 "$from$dir")
  echo -e $(date -Iseconds) "backup count: $count size: $du"

  # несколько попыток скопировать папку
  for try in {1..2}; do
    err=0

    # в случае копирования по дням может быть слишком много файлов, что приведет к таймаутам при листинге файлов в s3
    # поэтому дни копируем все равно поминутно, но в лок сохраняем по дням после всех копирований
    # если вылетит где-то то в lock файл не будет записан успех и папка будет повторна обработанна при следующем запуске.
    # parallel чтобы не было простоев между запусками (да они были),
    #  и не было простоев в самом копировании во время листинга файлов для проверки md5
    # таймауты 0 так как они регулируются на стороне самого s3
    set +e
    if [[ $mode == "s3" ]]; then
      if [[ $unit == "min" ]]; then
        aws --cli-connect-timeout 0 --cli-read-timeout 0 --endpoint-url "$s3_endpoint" s3 sync "$from$dir" "$s3_bucket$dir"
        err=$?
      elif [[ $unit == "day" ]]; then
        subdirs=$(ls "$from$dir")
        err=$?
        if [[ $err == 0 ]]; then
          parallel -j 2 -k "aws --cli-connect-timeout 0 --cli-read-timeout 0 --endpoint-url '$s3_endpoint' s3 sync '$from$dir{}/' '$s3_bucket$dir{}/' && echo '$from$dir{}/' ok" ::: $subdirs
          err=$?
        fi
      fi
    elif [[ $mode == "rsync" ]]; then
#      $sshCmd "$rsync_host" "mkdir -p $rsync_path$dir"
#      err=$?
#      if [[ $err == 0 ]]; then
#        rsync --stats -avPh -e "$sshCmd" "$from$dir" "$rsync_host:$rsync_path$dir"
#        err=$?
#      fi
      if [[ $removeSourceFiles == "true" ]]; then
        rsync --remove-source-files --info=progress2 --no-inc-recursive -ah -W  --rsync-path="mkdir -p $rsync_path$dir && rsync" -e "$sshCmd" "$from$dir" "$rsync_host:$rsync_path$dir"
        err=$?
        find "$from$dir" -depth -type d -empty -delete
      else
        rsync --inplace --info=progress2 --no-inc-recursive -ah -W  --rsync-path="mkdir -p $rsync_path$dir && rsync" -e "$sshCmd" "$from$dir" "$rsync_host:$rsync_path$dir"
        err=$?
      fi

    fi
    set -e

    # возможно случился timeout при обращении к s3, ждем минуту и продолжаем другие папки, эта папка будет перезапущенна уже при повторном запуске
    if [[ $err != 0 ]]; then
      onErrorSleepInterval=1m
      if [[ $unit == "min" ]]; then onErrorSleepInterval=30s; fi
      echo -e $(date -Iseconds) "failed backup $dir, ...sleep $onErrorSleepInterval"
      sleep $onErrorSleepInterval

      continue # пробуем еще раз если осталась попытка, либо идем к следующей папке
    fi

    # раз дошли до сюда то все ок, записываем в лок файл чтобы при повторном запуске игнорировать эту папку
    flock -w 3600 "$doneFile" -c "echo $tag >> $doneFile && sort -u -o $doneFile $doneFile"
    break # прервываем внутренний цикл так как все ок и больше не нужны попытки скопировать файлы
  done
done

echo $(date -Iseconds) ${#tagsString[@]} $unit $mode dirs backup DONE
