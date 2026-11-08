#!/usr/bin/env bash
# shellcheck disable=SC2329  # msg_<lang> functions are called indirectly as msg_${TW_LANG}
# ==============================================================================
# TimeWarp - macOS Time Machine Clone & Recovery Tool (APFS)
# Automated migration from a failing/healthy drive to a new destination drive.
# Languages: en (default), ru, es, de, fr, pt, zh
# Compatible with the stock macOS bash 3.2.
# ==============================================================================

set -e

# sudo strips the PATH; make Homebrew tools (ddrescue) discoverable
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# TIMEWARP_SELFTEST=1 is for tests/refusal_test.sh only: it skips the root, block-device
# and Full Disk Access checks so the safety checks can run against stubbed commands.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ------------------------------------------------------------------------------
# Translations. One function per language, English is the fallback.
# Placeholders use printf syntax (%s).
# ------------------------------------------------------------------------------
msg_en() {
  case "$1" in
    TITLE)          echo "macOS Time Machine Storage Migration & Recovery Tool" ;;
    ROOT_ERR)       echo "[Error] This script must be run as administrator." ;;
    ROOT_HINT)      echo "Run it with sudo: sudo %s" ;;
    STEP1)          echo "[1/6] Checking Terminal permissions..." ;;
    FDA_ERR)        echo "[Warning] Terminal does not have Full Disk Access." ;;
    FDA_PATH)       echo "Go to: System Settings -> Privacy & Security -> Full Disk Access" ;;
    FDA_ADD)        echo "Add and enable Terminal, then restart the script." ;;
    FDA_OK)         echo "✓ Raw block device access confirmed." ;;
    STEP2)          echo "[2/6] Connected storage devices:" ;;
    ASK_SRC)        echo "Enter the SOURCE disk identifier (for example, disk1): " ;;
    ASK_DST)        echo "Enter the TARGET disk identifier (for example, disk5): " ;;
    ERR_NOTFOUND)   echo "[Error] Disk %s not found!" ;;
    ERR_SAME)       echo "[Critical] Source and target disks are the same! Aborting." ;;
    WARN_ERASE)     echo "WARNING: All data on %s will be COMPLETELY DESTROYED!" ;;
    LBL_SRC)        echo "Source: %s" ;;
    LBL_DST)        echo "Target: %s" ;;
    ASK_CONFIRM)    echo "Are you absolutely sure? Type 'YES' to continue: " ;;
    CANCELLED)      echo "Operation cancelled by the user." ;;
    STEP3)          echo "[3/6] Checking %s for bad sectors..." ;;
    SMART_FAIL)     echo "⚠ Disk SMART status: FAILING (critical hardware failure)." ;;
    QUICK_READ)     echo "Sampling the disk at several positions to verify integrity..." ;;
    IO_ERR)         echo "⚠ I/O errors detected while reading the disk!" ;;
    READ_OK)        echo "✓ Read test completed successfully at all sampled positions." ;;
    STEP4)          echo "[4/6] Unmounting disks for safe cloning..." ;;
    STEP5)          echo "[5/6] Starting data transfer..." ;;
    USE_RESCUE)     echo "The disk has errors. Using GNU ddrescue with a recovery map." ;;
    DDRESCUE_MISSING) echo "ddrescue not found. Installing via Homebrew..." ;;
    BREW_ERR)       echo "[Error] ddrescue is missing and could not be installed automatically. Run 'brew install ddrescue' as a regular user (without sudo), then restart the script." ;;
    MAP_SAVED)      echo "The progress map will be saved to: %s" ;;
    RUN_RESCUE)     echo "Running ddrescue..." ;;
    USE_DD)         echo "The disk looks healthy. Using a standard raw block clone with dd." ;;
    RUN_DD)         echo "Running dd (64M block size)..." ;;
    STEP6)          echo "[6/6] Repairing the partition table and expanding the APFS container..." ;;
    APFS_FOUND)     echo "APFS partition found: /dev/%s" ;;
    RESIZING)       echo "Expanding the APFS container to the full capacity of the new drive..." ;;
    RESIZED)        echo "✓ APFS container expanded to the maximum size." ;;
    APFS_NOTFOUND)  echo "[Warning] APFS partition was not detected automatically." ;;
    CHECK_MANUAL)   echo "Check the layout manually with: diskutil list %s" ;;
    ERR_SIZEUNK)    echo "[Error] Could not determine the size of the source or target disk. Aborting." ;;
    ERR_SIZE)       echo "[Error] The target disk (%s GB) is smaller than the source disk (%s GB). Aborting." ;;
    DD_FAILED)      echo "⚠ dd failed during the transfer. Switching to ddrescue to finish the copy." ;;
    VERIFYING)      echo "Verifying volume %s..." ;;
    UNLOCK)         echo "Volume %s is locked. Enter its password when prompted:" ;;
    VERIFY_OK)      echo "✓ All volumes passed verification." ;;
    VERIFY_FAIL)    echo "⚠ Some volumes could not be verified. Run 'diskutil verifyVolume' manually and check the backup history in Time Machine before using the drive." ;;
    ERR_WHOLE)      echo "[Error] %s is not a whole physical disk. Use a whole disk such as disk2, not a partition such as disk2s2." ;;
    ERR_VIRTUAL)    echo "[Error] %s is a virtual APFS container, not a physical disk. Use the identifier of the physical disk." ;;
    ERR_SYSDISK)    echo "[Critical] %s holds the running system. Refusing to continue." ;;
    ERR_SYSUNK)     echo "[Critical] Could not reliably determine which physical disks hold the running system. Refusing to continue." ;;
    ERR_UNMOUNT)    echo "[Error] Could not unmount %s. Close every program using it and try again. Nothing was written." ;;
    MAP_EXISTS)     echo "A recovery map for exactly this pair of disks already exists: %s" ;;
    ASK_RESUME)     echo "Type RESUME to continue the interrupted migration, or NEW to start over (the old map will be archived): " ;;
    MAP_MISMATCH)   echo "[Error] The recovery map %s does not belong to this pair of disks. Move it away and retry." ;;
    RESCUE_CLEAN)   echo "✓ ddrescue read every block successfully." ;;
    RESCUE_LOSS)    echo "⚠ ddrescue could not recover %s bytes. Files stored in those areas may be damaged. Map: %s" ;;
    ERR_COPY)       echo "[Error] The copy did not finish. Run the script again with the same disks to resume from the recovery map." ;;
    ERR_RESIZE)     echo "[Error] Could not expand the APFS container." ;;
    NO_VOLUMES)     echo "⚠ No APFS volumes were found on the new container." ;;
    WARN_PARTIAL_TARGET)echo "⚠ The target disk may already be partially overwritten and is not usable yet." ;;
    HIST_HINT)      echo "Before erasing the old disk, confirm the history: add the new disk in System Settings -> General -> Time Machine and open 'Browse Time Machine Backups', or run 'tmutil listbackups'." ;;
    DONE_PARTIAL)   echo "Migration finished WITH WARNINGS: some data could not be recovered or verified. Do not erase the source disk." ;;
    DONE_FAILED)    echo "Migration FAILED. Do not erase the source disk. See the messages above." ;;
    ERR_NOAPFS)     echo "[Error] %s does not contain an APFS container. TimeWarp only migrates APFS Time Machine disks. Aborting." ;;
    MAP_CONTENT_MISMATCH)echo "[Error] The data on the target disk does not match the recovery map, so it is probably a different physical disk. Refusing to resume. Choose NEW to start over." ;;
    ERR_REPAIR)     echo "⚠ diskutil repairDisk reported an error on the target disk. The partition table may be damaged." ;;
    DONE)           echo "Migration completed successfully! The drive is ready to use." ;;
  esac
}

msg_ru() {
  case "$1" in
    TITLE)          echo "Инструмент миграции и восстановления Time Machine для macOS" ;;
    ROOT_ERR)       echo "[Ошибка] Скрипт должен быть запущен с правами администратора." ;;
    ROOT_HINT)      echo "Запустите через sudo: sudo %s" ;;
    STEP1)          echo "[1/6] Проверка системных разрешений Terminal..." ;;
    FDA_ERR)        echo "[Внимание] У Терминала нет «Полного доступа к диску» (Full Disk Access)." ;;
    FDA_PATH)       echo "Перейдите в: Системные настройки -> Конфиденциальность и безопасность -> Полный доступ к диску" ;;
    FDA_ADD)        echo "Добавьте и включите Terminal, затем перезапустите скрипт." ;;
    FDA_OK)         echo "✓ Доступ к блочным устройствам подтверждён." ;;
    STEP2)          echo "[2/6] Список подключённых накопителей:" ;;
    ASK_SRC)        echo "Введите идентификатор ИСХОДНОГО диска (например, disk1): " ;;
    ASK_DST)        echo "Введите идентификатор ЦЕЛЕВОГО диска (например, disk5): " ;;
    ERR_NOTFOUND)   echo "[Ошибка] Диск %s не найден!" ;;
    ERR_SAME)       echo "[Критическая ошибка] Исходный и целевой диск совпадают! Отмена." ;;
    WARN_ERASE)     echo "ВНИМАНИЕ: все данные на %s будут ПОЛНОСТЬЮ УНИЧТОЖЕНЫ!" ;;
    LBL_SRC)        echo "Источник: %s" ;;
    LBL_DST)        echo "Приёмник: %s" ;;
    ASK_CONFIRM)    echo "Вы абсолютно уверены? Введите 'YES' для продолжения: " ;;
    CANCELLED)      echo "Операция отменена пользователем." ;;
    STEP3)          echo "[3/6] Проверка накопителя %s на наличие сбойных секторов..." ;;
    SMART_FAIL)     echo "⚠ SMART-статус диска: FAILING (критический аппаратный сбой)." ;;
    QUICK_READ)     echo "Тест чтения в нескольких точках диска для проверки целостности..." ;;
    IO_ERR)         echo "⚠ Обнаружены ошибки ввода-вывода (I/O Errors) при чтении диска!" ;;
    READ_OK)        echo "✓ Тест чтения успешно пройден во всех проверенных точках." ;;
    STEP4)          echo "[4/6] Размонтирование дисков для безопасного клонирования..." ;;
    STEP5)          echo "[5/6] Запуск переноса данных..." ;;
    USE_RESCUE)     echo "Диск содержит ошибки. Используется GNU ddrescue с картой восстановления." ;;
    DDRESCUE_MISSING) echo "Утилита ddrescue не найдена. Устанавливаем через Homebrew..." ;;
    BREW_ERR)       echo "[Ошибка] ddrescue отсутствует и не может быть установлен автоматически. Выполните 'brew install ddrescue' от обычного пользователя (без sudo) и запустите скрипт снова." ;;
    MAP_SAVED)      echo "Карта прогресса будет сохранена в: %s" ;;
    RUN_RESCUE)     echo "Запуск ddrescue..." ;;
    USE_DD)         echo "Диск в норме. Используется стандартный блочный клон через dd." ;;
    RUN_DD)         echo "Запуск dd (размер блока 64M)..." ;;
    STEP6)          echo "[6/6] Восстановление таблицы разделов и расширение контейнера APFS..." ;;
    APFS_FOUND)     echo "Найден APFS-раздел: /dev/%s" ;;
    RESIZING)       echo "Расширяем контейнер APFS на весь объём нового накопителя..." ;;
    RESIZED)        echo "✓ Контейнер APFS расширен до максимума." ;;
    APFS_NOTFOUND)  echo "[Предупреждение] APFS-раздел не обнаружен автоматически." ;;
    CHECK_MANUAL)   echo "Проверьте разметку вручную: diskutil list %s" ;;
    ERR_SIZEUNK)    echo "[Ошибка] Не удалось определить размер исходного или целевого диска. Отмена." ;;
    ERR_SIZE)       echo "[Ошибка] Целевой диск (%s ГБ) меньше исходного (%s ГБ). Отмена." ;;
    DD_FAILED)      echo "⚠ dd завершился с ошибкой во время переноса. Переключаемся на ddrescue, чтобы закончить копирование." ;;
    VERIFYING)      echo "Проверка тома %s..." ;;
    UNLOCK)         echo "Том %s заблокирован. Введите его пароль, когда он будет запрошен:" ;;
    VERIFY_OK)      echo "✓ Все тома прошли проверку." ;;
    VERIFY_FAIL)    echo "⚠ Не все тома удалось проверить. Выполните 'diskutil verifyVolume' вручную и убедитесь, что история бэкапов видна в Time Machine, прежде чем использовать диск." ;;
    ERR_WHOLE)      echo "[Ошибка] %s — не целый физический диск. Укажите целый диск, например disk2, а не раздел вроде disk2s2." ;;
    ERR_VIRTUAL)    echo "[Ошибка] %s — виртуальный контейнер APFS, а не физический диск. Укажите идентификатор физического диска." ;;
    ERR_SYSDISK)    echo "[Критическая ошибка] %s содержит запущенную систему. Продолжение запрещено." ;;
    ERR_SYSUNK)     echo "[Критическая ошибка] Не удалось надёжно определить, какие физические диски содержат запущенную систему. Продолжение запрещено." ;;
    ERR_UNMOUNT)    echo "[Ошибка] Не удалось размонтировать %s. Закройте все программы, использующие его, и повторите. Ничего не записано." ;;
    MAP_EXISTS)     echo "Карта восстановления для именно этой пары дисков уже существует: %s" ;;
    ASK_RESUME)     echo "Введите RESUME, чтобы продолжить прерванную миграцию, или NEW, чтобы начать заново (старая карта будет архивирована): " ;;
    MAP_MISMATCH)   echo "[Ошибка] Карта восстановления %s не относится к этой паре дисков. Уберите её и повторите." ;;
    RESCUE_CLEAN)   echo "✓ ddrescue успешно прочитал все блоки." ;;
    RESCUE_LOSS)    echo "⚠ ddrescue не смог восстановить %s байт. Файлы в этих областях могут быть повреждены. Карта: %s" ;;
    ERR_COPY)       echo "[Ошибка] Копирование не завершено. Запустите скрипт снова с теми же дисками, чтобы продолжить по карте восстановления." ;;
    ERR_RESIZE)     echo "[Ошибка] Не удалось расширить контейнер APFS." ;;
    NO_VOLUMES)     echo "⚠ В новом контейнере не найдено ни одного тома APFS." ;;
    WARN_PARTIAL_TARGET)echo "⚠ Целевой диск мог быть уже частично перезаписан и пока непригоден к использованию." ;;
    HIST_HINT)      echo "Прежде чем стирать старый диск, проверьте историю: добавьте новый диск в Системные настройки -> Основные -> Time Machine и откройте 'Просмотр резервных копий Time Machine' или выполните 'tmutil listbackups'." ;;
    DONE_PARTIAL)   echo "Миграция завершена С ПРЕДУПРЕЖДЕНИЯМИ: часть данных не удалось восстановить или проверить. Не стирайте исходный диск." ;;
    DONE_FAILED)    echo "Миграция НЕ УДАЛАСЬ. Не стирайте исходный диск. См. сообщения выше." ;;
    ERR_NOAPFS)     echo "[Ошибка] %s не содержит контейнера APFS. TimeWarp переносит только диски Time Machine с APFS. Отмена." ;;
    MAP_CONTENT_MISMATCH)echo "[Ошибка] Данные на целевом диске не совпадают с картой восстановления, скорее всего это другой физический диск. Возобновление отклонено. Выберите NEW, чтобы начать заново." ;;
    ERR_REPAIR)     echo "⚠ diskutil repairDisk сообщил об ошибке на целевом диске. Таблица разделов могла быть повреждена." ;;
    DONE)           echo "Миграция успешно завершена! Диск готов к использованию." ;;
  esac
}

msg_es() {
  case "$1" in
    TITLE)          echo "Herramienta de migración y recuperación de Time Machine para macOS" ;;
    ROOT_ERR)       echo "[Error] Este script debe ejecutarse como administrador." ;;
    ROOT_HINT)      echo "Ejecútalo con sudo: sudo %s" ;;
    STEP1)          echo "[1/6] Comprobando los permisos de Terminal..." ;;
    FDA_ERR)        echo "[Aviso] Terminal no tiene acceso total al disco (Full Disk Access)." ;;
    FDA_PATH)       echo "Ve a: Ajustes del Sistema -> Privacidad y seguridad -> Acceso total al disco" ;;
    FDA_ADD)        echo "Añade y activa Terminal, y vuelve a ejecutar el script." ;;
    FDA_OK)         echo "✓ Acceso a los dispositivos de bloque confirmado." ;;
    STEP2)          echo "[2/6] Dispositivos de almacenamiento conectados:" ;;
    ASK_SRC)        echo "Introduce el identificador del disco de ORIGEN (por ejemplo, disk1): " ;;
    ASK_DST)        echo "Introduce el identificador del disco de DESTINO (por ejemplo, disk5): " ;;
    ERR_NOTFOUND)   echo "[Error] ¡No se encontró el disco %s!" ;;
    ERR_SAME)       echo "[Crítico] ¡El disco de origen y el de destino son el mismo! Cancelando." ;;
    WARN_ERASE)     echo "ATENCIÓN: ¡todos los datos de %s se DESTRUIRÁN por completo!" ;;
    LBL_SRC)        echo "Origen: %s" ;;
    LBL_DST)        echo "Destino: %s" ;;
    ASK_CONFIRM)    echo "¿Estás completamente seguro? Escribe 'YES' para continuar: " ;;
    CANCELLED)      echo "Operación cancelada por el usuario." ;;
    STEP3)          echo "[3/6] Buscando sectores defectuosos en %s..." ;;
    SMART_FAIL)     echo "⚠ Estado SMART del disco: FAILING (fallo crítico de hardware)." ;;
    QUICK_READ)     echo "Leyendo el disco en varias posiciones para verificar la integridad..." ;;
    IO_ERR)         echo "⚠ ¡Se detectaron errores de E/S al leer el disco!" ;;
    READ_OK)        echo "✓ La prueba de lectura terminó correctamente en todas las posiciones." ;;
    STEP4)          echo "[4/6] Desmontando los discos para una clonación segura..." ;;
    STEP5)          echo "[5/6] Iniciando la transferencia de datos..." ;;
    USE_RESCUE)     echo "El disco tiene errores. Se usará GNU ddrescue con un mapa de recuperación." ;;
    DDRESCUE_MISSING) echo "No se encontró ddrescue. Instalando con Homebrew..." ;;
    BREW_ERR)       echo "[Error] Falta ddrescue y no se pudo instalar automáticamente. Ejecuta 'brew install ddrescue' como usuario normal (sin sudo) y vuelve a ejecutar el script." ;;
    MAP_SAVED)      echo "El mapa de progreso se guardará en: %s" ;;
    RUN_RESCUE)     echo "Ejecutando ddrescue..." ;;
    USE_DD)         echo "El disco parece estar sano. Se usará un clon de bloques estándar con dd." ;;
    RUN_DD)         echo "Ejecutando dd (tamaño de bloque 64M)..." ;;
    STEP6)          echo "[6/6] Reparando la tabla de particiones y ampliando el contenedor APFS..." ;;
    APFS_FOUND)     echo "Partición APFS encontrada: /dev/%s" ;;
    RESIZING)       echo "Ampliando el contenedor APFS a toda la capacidad del nuevo disco..." ;;
    RESIZED)        echo "✓ Contenedor APFS ampliado al tamaño máximo." ;;
    APFS_NOTFOUND)  echo "[Aviso] No se detectó automáticamente la partición APFS." ;;
    CHECK_MANUAL)   echo "Revisa el esquema manualmente con: diskutil list %s" ;;
    ERR_SIZEUNK)    echo "[Error] No se pudo determinar el tamaño del disco de origen o de destino. Cancelando." ;;
    ERR_SIZE)       echo "[Error] El disco de destino (%s GB) es más pequeño que el de origen (%s GB). Cancelando." ;;
    DD_FAILED)      echo "⚠ dd falló durante la transferencia. Cambiando a ddrescue para terminar la copia." ;;
    VERIFYING)      echo "Verificando el volumen %s..." ;;
    UNLOCK)         echo "El volumen %s está bloqueado. Introduce su contraseña cuando se solicite:" ;;
    VERIFY_OK)      echo "✓ Todos los volúmenes pasaron la verificación." ;;
    VERIFY_FAIL)    echo "⚠ No se pudieron verificar algunos volúmenes. Ejecuta 'diskutil verifyVolume' manualmente y comprueba el historial de copias en Time Machine antes de usar el disco." ;;
    ERR_WHOLE)      echo "[Error] %s no es un disco físico completo. Usa un disco completo como disk2, no una partición como disk2s2." ;;
    ERR_VIRTUAL)    echo "[Error] %s es un contenedor APFS virtual, no un disco físico. Usa el identificador del disco físico." ;;
    ERR_SYSDISK)    echo "[Crítico] %s contiene el sistema en ejecución. Se rechaza continuar." ;;
    ERR_SYSUNK)     echo "[Crítico] No se pudo determinar con certeza qué discos físicos contienen el sistema en ejecución. Se rechaza continuar." ;;
    ERR_UNMOUNT)    echo "[Error] No se pudo desmontar %s. Cierra todos los programas que lo usen e inténtalo de nuevo. No se escribió nada." ;;
    MAP_EXISTS)     echo "Ya existe un mapa de recuperación para exactamente este par de discos: %s" ;;
    ASK_RESUME)     echo "Escribe RESUME para continuar la migración interrumpida, o NEW para empezar de nuevo (el mapa anterior se archivará): " ;;
    MAP_MISMATCH)   echo "[Error] El mapa de recuperación %s no pertenece a este par de discos. Muévelo y vuelve a intentarlo." ;;
    RESCUE_CLEAN)   echo "✓ ddrescue leyó todos los bloques correctamente." ;;
    RESCUE_LOSS)    echo "⚠ ddrescue no pudo recuperar %s bytes. Los archivos de esas zonas pueden estar dañados. Mapa: %s" ;;
    ERR_COPY)       echo "[Error] La copia no terminó. Ejecuta el script de nuevo con los mismos discos para continuar desde el mapa de recuperación." ;;
    ERR_RESIZE)     echo "[Error] No se pudo ampliar el contenedor APFS." ;;
    NO_VOLUMES)     echo "⚠ No se encontró ningún volumen APFS en el nuevo contenedor." ;;
    WARN_PARTIAL_TARGET)echo "⚠ El disco de destino puede estar ya parcialmente sobrescrito y todavía no se puede usar." ;;
    HIST_HINT)      echo "Antes de borrar el disco antiguo, confirma el historial: añade el disco nuevo en Ajustes del Sistema -> General -> Time Machine y abre 'Explorar copias de seguridad de Time Machine', o ejecuta 'tmutil listbackups'." ;;
    DONE_PARTIAL)   echo "Migración terminada CON ADVERTENCIAS: no se pudieron recuperar o verificar algunos datos. No borres el disco de origen." ;;
    DONE_FAILED)    echo "La migración FALLÓ. No borres el disco de origen. Consulta los mensajes anteriores." ;;
    ERR_NOAPFS)     echo "[Error] %s no contiene un contenedor APFS. TimeWarp solo migra discos de Time Machine con APFS. Cancelando." ;;
    MAP_CONTENT_MISMATCH)echo "[Error] Los datos del disco de destino no coinciden con el mapa de recuperación, por lo que probablemente es otro disco físico. Se rechaza reanudar. Elige NEW para empezar de nuevo." ;;
    ERR_REPAIR)     echo "⚠ diskutil repairDisk informó de un error en el disco de destino. La tabla de particiones podría estar dañada." ;;
    DONE)           echo "¡Migración completada con éxito! El disco está listo para usarse." ;;
  esac
}

msg_de() {
  case "$1" in
    TITLE)          echo "Time-Machine-Migrations- und Wiederherstellungstool für macOS" ;;
    ROOT_ERR)       echo "[Fehler] Dieses Skript muss als Administrator ausgeführt werden." ;;
    ROOT_HINT)      echo "Mit sudo starten: sudo %s" ;;
    STEP1)          echo "[1/6] Terminal-Berechtigungen werden geprüft..." ;;
    FDA_ERR)        echo "[Warnung] Das Terminal hat keinen Vollzugriff auf die Festplatte (Full Disk Access)." ;;
    FDA_PATH)       echo "Öffne: Systemeinstellungen -> Datenschutz & Sicherheit -> Voller Festplattenzugriff" ;;
    FDA_ADD)        echo "Füge das Terminal hinzu, aktiviere es und starte das Skript neu." ;;
    FDA_OK)         echo "✓ Zugriff auf Blockgeräte bestätigt." ;;
    STEP2)          echo "[2/6] Angeschlossene Speichergeräte:" ;;
    ASK_SRC)        echo "Gib die Kennung des QUELLLAUFWERKS ein (z. B. disk1): " ;;
    ASK_DST)        echo "Gib die Kennung des ZIELLAUFWERKS ein (z. B. disk5): " ;;
    ERR_NOTFOUND)   echo "[Fehler] Laufwerk %s nicht gefunden!" ;;
    ERR_SAME)       echo "[Kritisch] Quell- und Ziellaufwerk sind identisch! Abbruch." ;;
    WARN_ERASE)     echo "ACHTUNG: Alle Daten auf %s werden VOLLSTÄNDIG GELÖSCHT!" ;;
    LBL_SRC)        echo "Quelle: %s" ;;
    LBL_DST)        echo "Ziel: %s" ;;
    ASK_CONFIRM)    echo "Bist du absolut sicher? Tippe 'YES', um fortzufahren: " ;;
    CANCELLED)      echo "Vorgang vom Benutzer abgebrochen." ;;
    STEP3)          echo "[3/6] %s wird auf defekte Sektoren geprüft..." ;;
    SMART_FAIL)     echo "⚠ SMART-Status der Festplatte: FAILING (kritischer Hardwarefehler)." ;;
    QUICK_READ)     echo "Die Festplatte wird an mehreren Positionen gelesen, um die Integrität zu prüfen..." ;;
    IO_ERR)         echo "⚠ Beim Lesen der Festplatte wurden E/A-Fehler erkannt!" ;;
    READ_OK)        echo "✓ Lesetest an allen geprüften Positionen erfolgreich abgeschlossen." ;;
    STEP4)          echo "[4/6] Laufwerke werden für sicheres Klonen ausgehängt..." ;;
    STEP5)          echo "[5/6] Datenübertragung wird gestartet..." ;;
    USE_RESCUE)     echo "Die Festplatte hat Fehler. GNU ddrescue mit Wiederherstellungskarte wird verwendet." ;;
    DDRESCUE_MISSING) echo "ddrescue nicht gefunden. Installation über Homebrew..." ;;
    BREW_ERR)       echo "[Fehler] ddrescue fehlt und konnte nicht automatisch installiert werden. Führe 'brew install ddrescue' als normaler Benutzer (ohne sudo) aus und starte das Skript neu." ;;
    MAP_SAVED)      echo "Die Fortschrittskarte wird gespeichert unter: %s" ;;
    RUN_RESCUE)     echo "ddrescue wird gestartet..." ;;
    USE_DD)         echo "Die Festplatte ist in Ordnung. Ein Standard-Blockklon mit dd wird verwendet." ;;
    RUN_DD)         echo "dd wird gestartet (Blockgröße 64M)..." ;;
    STEP6)          echo "[6/6] Partitionstabelle wird repariert und APFS-Container erweitert..." ;;
    APFS_FOUND)     echo "APFS-Partition gefunden: /dev/%s" ;;
    RESIZING)       echo "APFS-Container wird auf die volle Kapazität des neuen Laufwerks erweitert..." ;;
    RESIZED)        echo "✓ APFS-Container auf die maximale Größe erweitert." ;;
    APFS_NOTFOUND)  echo "[Warnung] Die APFS-Partition wurde nicht automatisch erkannt." ;;
    CHECK_MANUAL)   echo "Prüfe das Layout manuell mit: diskutil list %s" ;;
    ERR_SIZEUNK)    echo "[Fehler] Die Größe des Quell- oder Ziellaufwerks konnte nicht ermittelt werden. Abbruch." ;;
    ERR_SIZE)       echo "[Fehler] Das Ziellaufwerk (%s GB) ist kleiner als das Quelllaufwerk (%s GB). Abbruch." ;;
    DD_FAILED)      echo "⚠ dd ist während der Übertragung fehlgeschlagen. Wechsel zu ddrescue, um das Kopieren abzuschließen." ;;
    VERIFYING)      echo "Volume %s wird geprüft..." ;;
    UNLOCK)         echo "Volume %s ist gesperrt. Gib das Passwort ein, sobald du danach gefragt wirst:" ;;
    VERIFY_OK)      echo "✓ Alle Volumes haben die Prüfung bestanden." ;;
    VERIFY_FAIL)    echo "⚠ Einige Volumes konnten nicht geprüft werden. Führe 'diskutil verifyVolume' manuell aus und prüfe den Backup-Verlauf in Time Machine, bevor du das Laufwerk verwendest." ;;
    ERR_WHOLE)      echo "[Fehler] %s ist kein vollständiges physisches Laufwerk. Verwende ein ganzes Laufwerk wie disk2, keine Partition wie disk2s2." ;;
    ERR_VIRTUAL)    echo "[Fehler] %s ist ein virtueller APFS-Container, kein physisches Laufwerk. Verwende die Kennung des physischen Laufwerks." ;;
    ERR_SYSDISK)    echo "[Kritisch] %s enthält das laufende System. Fortsetzung verweigert." ;;
    ERR_SYSUNK)     echo "[Kritisch] Es konnte nicht zuverlässig ermittelt werden, welche physischen Laufwerke das laufende System enthalten. Fortsetzung verweigert." ;;
    ERR_UNMOUNT)    echo "[Fehler] %s konnte nicht ausgehängt werden. Schließe alle Programme, die es verwenden, und versuche es erneut. Es wurde nichts geschrieben." ;;
    MAP_EXISTS)     echo "Für genau dieses Laufwerkspaar existiert bereits eine Wiederherstellungskarte: %s" ;;
    ASK_RESUME)     echo "Gib RESUME ein, um die unterbrochene Migration fortzusetzen, oder NEW, um neu zu beginnen (die alte Karte wird archiviert): " ;;
    MAP_MISMATCH)   echo "[Fehler] Die Wiederherstellungskarte %s gehört nicht zu diesem Laufwerkspaar. Verschiebe sie und versuche es erneut." ;;
    RESCUE_CLEAN)   echo "✓ ddrescue hat alle Blöcke erfolgreich gelesen." ;;
    RESCUE_LOSS)    echo "⚠ ddrescue konnte %s Bytes nicht wiederherstellen. Dateien in diesen Bereichen können beschädigt sein. Karte: %s" ;;
    ERR_COPY)       echo "[Fehler] Das Kopieren wurde nicht abgeschlossen. Starte das Skript erneut mit denselben Laufwerken, um anhand der Wiederherstellungskarte fortzufahren." ;;
    ERR_RESIZE)     echo "[Fehler] Der APFS-Container konnte nicht erweitert werden." ;;
    NO_VOLUMES)     echo "⚠ Im neuen Container wurden keine APFS-Volumes gefunden." ;;
    WARN_PARTIAL_TARGET)echo "⚠ Das Ziellaufwerk ist möglicherweise bereits teilweise überschrieben und noch nicht verwendbar." ;;
    HIST_HINT)      echo "Bevor du das alte Laufwerk löschst, prüfe den Verlauf: Füge das neue Laufwerk unter Systemeinstellungen -> Allgemein -> Time Machine hinzu und öffne 'Time-Machine-Backups durchsuchen' oder führe 'tmutil listbackups' aus." ;;
    DONE_PARTIAL)   echo "Migration MIT WARNUNGEN beendet: Einige Daten konnten nicht wiederhergestellt oder geprüft werden. Lösche das Quelllaufwerk nicht." ;;
    DONE_FAILED)    echo "Migration FEHLGESCHLAGEN. Lösche das Quelllaufwerk nicht. Siehe die Meldungen oben." ;;
    ERR_NOAPFS)     echo "[Fehler] %s enthält keinen APFS-Container. TimeWarp migriert nur Time-Machine-Laufwerke mit APFS. Abbruch." ;;
    MAP_CONTENT_MISMATCH)echo "[Fehler] Die Daten auf dem Ziellaufwerk passen nicht zur Wiederherstellungskarte, es handelt sich wahrscheinlich um ein anderes physisches Laufwerk. Fortsetzung verweigert. Wähle NEW, um neu zu beginnen." ;;
    ERR_REPAIR)     echo "⚠ diskutil repairDisk meldete einen Fehler auf dem Ziellaufwerk. Die Partitionstabelle könnte beschädigt sein." ;;
    DONE)           echo "Migration erfolgreich abgeschlossen! Das Laufwerk ist einsatzbereit." ;;
  esac
}

msg_fr() {
  case "$1" in
    TITLE)          echo "Outil de migration et de récupération Time Machine pour macOS" ;;
    ROOT_ERR)       echo "[Erreur] Ce script doit être exécuté en tant qu'administrateur." ;;
    ROOT_HINT)      echo "Lancez-le avec sudo : sudo %s" ;;
    STEP1)          echo "[1/6] Vérification des autorisations de Terminal..." ;;
    FDA_ERR)        echo "[Attention] Terminal n'a pas l'accès complet au disque (Full Disk Access)." ;;
    FDA_PATH)       echo "Allez dans : Réglages Système -> Confidentialité et sécurité -> Accès complet au disque" ;;
    FDA_ADD)        echo "Ajoutez et activez Terminal, puis relancez le script." ;;
    FDA_OK)         echo "✓ Accès aux périphériques bloc confirmé." ;;
    STEP2)          echo "[2/6] Périphériques de stockage connectés :" ;;
    ASK_SRC)        echo "Saisissez l'identifiant du disque SOURCE (par exemple, disk1) : " ;;
    ASK_DST)        echo "Saisissez l'identifiant du disque CIBLE (par exemple, disk5) : " ;;
    ERR_NOTFOUND)   echo "[Erreur] Disque %s introuvable !" ;;
    ERR_SAME)       echo "[Critique] Le disque source et le disque cible sont identiques ! Annulation." ;;
    WARN_ERASE)     echo "ATTENTION : toutes les données de %s seront DÉTRUITES définitivement !" ;;
    LBL_SRC)        echo "Source : %s" ;;
    LBL_DST)        echo "Cible : %s" ;;
    ASK_CONFIRM)    echo "Êtes-vous absolument sûr ? Tapez 'YES' pour continuer : " ;;
    CANCELLED)      echo "Opération annulée par l'utilisateur." ;;
    STEP3)          echo "[3/6] Recherche de secteurs défectueux sur %s..." ;;
    SMART_FAIL)     echo "⚠ État SMART du disque : FAILING (défaillance matérielle critique)." ;;
    QUICK_READ)     echo "Lecture du disque à plusieurs endroits pour vérifier l'intégrité..." ;;
    IO_ERR)         echo "⚠ Erreurs d'E/S détectées lors de la lecture du disque !" ;;
    READ_OK)        echo "✓ Le test de lecture s'est terminé avec succès à tous les endroits testés." ;;
    STEP4)          echo "[4/6] Démontage des disques pour un clonage sûr..." ;;
    STEP5)          echo "[5/6] Lancement du transfert des données..." ;;
    USE_RESCUE)     echo "Le disque contient des erreurs. Utilisation de GNU ddrescue avec une carte de récupération." ;;
    DDRESCUE_MISSING) echo "ddrescue introuvable. Installation via Homebrew..." ;;
    BREW_ERR)       echo "[Erreur] ddrescue est absent et n'a pas pu être installé automatiquement. Exécutez 'brew install ddrescue' en tant qu'utilisateur normal (sans sudo), puis relancez le script." ;;
    MAP_SAVED)      echo "La carte de progression sera enregistrée dans : %s" ;;
    RUN_RESCUE)     echo "Lancement de ddrescue..." ;;
    USE_DD)         echo "Le disque semble sain. Utilisation d'un clone de blocs standard avec dd." ;;
    RUN_DD)         echo "Lancement de dd (taille de bloc 64M)..." ;;
    STEP6)          echo "[6/6] Réparation de la table de partitions et extension du conteneur APFS..." ;;
    APFS_FOUND)     echo "Partition APFS trouvée : /dev/%s" ;;
    RESIZING)       echo "Extension du conteneur APFS à toute la capacité du nouveau disque..." ;;
    RESIZED)        echo "✓ Conteneur APFS étendu à la taille maximale." ;;
    APFS_NOTFOUND)  echo "[Attention] La partition APFS n'a pas été détectée automatiquement." ;;
    CHECK_MANUAL)   echo "Vérifiez la disposition manuellement avec : diskutil list %s" ;;
    ERR_SIZEUNK)    echo "[Erreur] Impossible de déterminer la taille du disque source ou cible. Annulation." ;;
    ERR_SIZE)       echo "[Erreur] Le disque cible (%s Go) est plus petit que le disque source (%s Go). Annulation." ;;
    DD_FAILED)      echo "⚠ dd a échoué pendant le transfert. Passage à ddrescue pour terminer la copie." ;;
    VERIFYING)      echo "Vérification du volume %s..." ;;
    UNLOCK)         echo "Le volume %s est verrouillé. Saisissez son mot de passe lorsqu'il vous est demandé :" ;;
    VERIFY_OK)      echo "✓ Tous les volumes ont réussi la vérification." ;;
    VERIFY_FAIL)    echo "⚠ Certains volumes n'ont pas pu être vérifiés. Exécutez 'diskutil verifyVolume' manuellement et vérifiez l'historique des sauvegardes dans Time Machine avant d'utiliser le disque." ;;
    ERR_WHOLE)      echo "[Erreur] %s n'est pas un disque physique entier. Utilisez un disque entier comme disk2, et non une partition comme disk2s2." ;;
    ERR_VIRTUAL)    echo "[Erreur] %s est un conteneur APFS virtuel, pas un disque physique. Utilisez l'identifiant du disque physique." ;;
    ERR_SYSDISK)    echo "[Critique] %s contient le système en cours d'exécution. Poursuite refusée." ;;
    ERR_SYSUNK)     echo "[Critique] Impossible de déterminer de façon fiable quels disques physiques contiennent le système en cours d'exécution. Poursuite refusée." ;;
    ERR_UNMOUNT)    echo "[Erreur] Impossible de démonter %s. Fermez tous les programmes qui l'utilisent et réessayez. Rien n'a été écrit." ;;
    MAP_EXISTS)     echo "Une carte de récupération existe déjà pour exactement cette paire de disques : %s" ;;
    ASK_RESUME)     echo "Tapez RESUME pour reprendre la migration interrompue, ou NEW pour recommencer (l'ancienne carte sera archivée) : " ;;
    MAP_MISMATCH)   echo "[Erreur] La carte de récupération %s n'appartient pas à cette paire de disques. Déplacez-la et réessayez." ;;
    RESCUE_CLEAN)   echo "✓ ddrescue a lu tous les blocs avec succès." ;;
    RESCUE_LOSS)    echo "⚠ ddrescue n'a pas pu récupérer %s octets. Les fichiers situés dans ces zones peuvent être endommagés. Carte : %s" ;;
    ERR_COPY)       echo "[Erreur] La copie ne s'est pas terminée. Relancez le script avec les mêmes disques pour reprendre à partir de la carte de récupération." ;;
    ERR_RESIZE)     echo "[Erreur] Impossible d'étendre le conteneur APFS." ;;
    NO_VOLUMES)     echo "⚠ Aucun volume APFS n'a été trouvé dans le nouveau conteneur." ;;
    WARN_PARTIAL_TARGET)echo "⚠ Le disque cible est peut-être déjà partiellement écrasé et n'est pas encore utilisable." ;;
    HIST_HINT)      echo "Avant d'effacer l'ancien disque, vérifiez l'historique : ajoutez le nouveau disque dans Réglages Système -> Général -> Time Machine et ouvrez 'Parcourir les sauvegardes Time Machine', ou exécutez 'tmutil listbackups'." ;;
    DONE_PARTIAL)   echo "Migration terminée AVEC DES AVERTISSEMENTS : certaines données n'ont pas pu être récupérées ou vérifiées. N'effacez pas le disque source." ;;
    DONE_FAILED)    echo "La migration a ÉCHOUÉ. N'effacez pas le disque source. Consultez les messages ci-dessus." ;;
    ERR_NOAPFS)     echo "[Erreur] %s ne contient pas de conteneur APFS. TimeWarp ne migre que les disques Time Machine en APFS. Annulation." ;;
    MAP_CONTENT_MISMATCH)echo "[Erreur] Les données du disque cible ne correspondent pas à la carte de récupération : il s'agit probablement d'un autre disque physique. Reprise refusée. Choisissez NEW pour recommencer." ;;
    ERR_REPAIR)     echo "⚠ diskutil repairDisk a signalé une erreur sur le disque cible. La table de partitions est peut-être endommagée." ;;
    DONE)           echo "Migration terminée avec succès ! Le disque est prêt à l'emploi." ;;
  esac
}

msg_pt() {
  case "$1" in
    TITLE)          echo "Ferramenta de migração e recuperação do Time Machine para macOS" ;;
    ROOT_ERR)       echo "[Erro] Este script deve ser executado como administrador." ;;
    ROOT_HINT)      echo "Execute com sudo: sudo %s" ;;
    STEP1)          echo "[1/6] Verificando as permissões do Terminal..." ;;
    FDA_ERR)        echo "[Aviso] O Terminal não tem Acesso Total ao Disco (Full Disk Access)." ;;
    FDA_PATH)       echo "Vá em: Ajustes do Sistema -> Privacidade e Segurança -> Acesso Total ao Disco" ;;
    FDA_ADD)        echo "Adicione e ative o Terminal, depois reinicie o script." ;;
    FDA_OK)         echo "✓ Acesso aos dispositivos de bloco confirmado." ;;
    STEP2)          echo "[2/6] Dispositivos de armazenamento conectados:" ;;
    ASK_SRC)        echo "Digite o identificador do disco de ORIGEM (por exemplo, disk1): " ;;
    ASK_DST)        echo "Digite o identificador do disco de DESTINO (por exemplo, disk5): " ;;
    ERR_NOTFOUND)   echo "[Erro] Disco %s não encontrado!" ;;
    ERR_SAME)       echo "[Crítico] O disco de origem e o de destino são o mesmo! Cancelando." ;;
    WARN_ERASE)     echo "ATENÇÃO: todos os dados em %s serão DESTRUÍDOS por completo!" ;;
    LBL_SRC)        echo "Origem: %s" ;;
    LBL_DST)        echo "Destino: %s" ;;
    ASK_CONFIRM)    echo "Você tem certeza absoluta? Digite 'YES' para continuar: " ;;
    CANCELLED)      echo "Operação cancelada pelo usuário." ;;
    STEP3)          echo "[3/6] Verificando setores defeituosos em %s..." ;;
    SMART_FAIL)     echo "⚠ Status SMART do disco: FAILING (falha crítica de hardware)." ;;
    QUICK_READ)     echo "Lendo o disco em várias posições para verificar a integridade..." ;;
    IO_ERR)         echo "⚠ Erros de E/S detectados durante a leitura do disco!" ;;
    READ_OK)        echo "✓ O teste de leitura foi concluído com sucesso em todas as posições." ;;
    STEP4)          echo "[4/6] Desmontando os discos para clonagem segura..." ;;
    STEP5)          echo "[5/6] Iniciando a transferência de dados..." ;;
    USE_RESCUE)     echo "O disco tem erros. Usando GNU ddrescue com mapa de recuperação." ;;
    DDRESCUE_MISSING) echo "ddrescue não encontrado. Instalando via Homebrew..." ;;
    BREW_ERR)       echo "[Erro] O ddrescue não está instalado e não pôde ser instalado automaticamente. Execute 'brew install ddrescue' como usuário normal (sem sudo) e reinicie o script." ;;
    MAP_SAVED)      echo "O mapa de progresso será salvo em: %s" ;;
    RUN_RESCUE)     echo "Executando o ddrescue..." ;;
    USE_DD)         echo "O disco parece saudável. Usando um clone de blocos padrão com dd." ;;
    RUN_DD)         echo "Executando o dd (tamanho do bloco 64M)..." ;;
    STEP6)          echo "[6/6] Reparando a tabela de partições e expandindo o contêiner APFS..." ;;
    APFS_FOUND)     echo "Partição APFS encontrada: /dev/%s" ;;
    RESIZING)       echo "Expandindo o contêiner APFS para toda a capacidade do novo disco..." ;;
    RESIZED)        echo "✓ Contêiner APFS expandido ao tamanho máximo." ;;
    APFS_NOTFOUND)  echo "[Aviso] A partição APFS não foi detectada automaticamente." ;;
    CHECK_MANUAL)   echo "Verifique o layout manualmente com: diskutil list %s" ;;
    ERR_SIZEUNK)    echo "[Erro] Não foi possível determinar o tamanho do disco de origem ou de destino. Cancelando." ;;
    ERR_SIZE)       echo "[Erro] O disco de destino (%s GB) é menor que o disco de origem (%s GB). Cancelando." ;;
    DD_FAILED)      echo "⚠ O dd falhou durante a transferência. Mudando para o ddrescue para concluir a cópia." ;;
    VERIFYING)      echo "Verificando o volume %s..." ;;
    UNLOCK)         echo "O volume %s está bloqueado. Digite a senha quando for solicitada:" ;;
    VERIFY_OK)      echo "✓ Todos os volumes passaram na verificação." ;;
    VERIFY_FAIL)    echo "⚠ Alguns volumes não puderam ser verificados. Execute 'diskutil verifyVolume' manualmente e confira o histórico de backups no Time Machine antes de usar o disco." ;;
    ERR_WHOLE)      echo "[Erro] %s não é um disco físico inteiro. Use um disco inteiro como disk2, não uma partição como disk2s2." ;;
    ERR_VIRTUAL)    echo "[Erro] %s é um contêiner APFS virtual, não um disco físico. Use o identificador do disco físico." ;;
    ERR_SYSDISK)    echo "[Crítico] %s contém o sistema em execução. Continuação recusada." ;;
    ERR_SYSUNK)     echo "[Crítico] Não foi possível determinar com segurança quais discos físicos contêm o sistema em execução. Continuação recusada." ;;
    ERR_UNMOUNT)    echo "[Erro] Não foi possível desmontar %s. Feche todos os programas que o usam e tente novamente. Nada foi gravado." ;;
    MAP_EXISTS)     echo "Já existe um mapa de recuperação para exatamente este par de discos: %s" ;;
    ASK_RESUME)     echo "Digite RESUME para continuar a migração interrompida, ou NEW para recomeçar (o mapa antigo será arquivado): " ;;
    MAP_MISMATCH)   echo "[Erro] O mapa de recuperação %s não pertence a este par de discos. Mova-o e tente novamente." ;;
    RESCUE_CLEAN)   echo "✓ O ddrescue leu todos os blocos com sucesso." ;;
    RESCUE_LOSS)    echo "⚠ O ddrescue não conseguiu recuperar %s bytes. Arquivos nessas áreas podem estar danificados. Mapa: %s" ;;
    ERR_COPY)       echo "[Erro] A cópia não foi concluída. Execute o script novamente com os mesmos discos para continuar a partir do mapa de recuperação." ;;
    ERR_RESIZE)     echo "[Erro] Não foi possível expandir o contêiner APFS." ;;
    NO_VOLUMES)     echo "⚠ Nenhum volume APFS foi encontrado no novo contêiner." ;;
    WARN_PARTIAL_TARGET)echo "⚠ O disco de destino pode já estar parcialmente sobrescrito e ainda não pode ser usado." ;;
    HIST_HINT)      echo "Antes de apagar o disco antigo, confirme o histórico: adicione o novo disco em Ajustes do Sistema -> Geral -> Time Machine e abra 'Navegar pelos backups do Time Machine', ou execute 'tmutil listbackups'." ;;
    DONE_PARTIAL)   echo "Migração concluída COM AVISOS: alguns dados não puderam ser recuperados ou verificados. Não apague o disco de origem." ;;
    DONE_FAILED)    echo "A migração FALHOU. Não apague o disco de origem. Veja as mensagens acima." ;;
    ERR_NOAPFS)     echo "[Erro] %s não contém um contêiner APFS. O TimeWarp só migra discos do Time Machine com APFS. Cancelando." ;;
    MAP_CONTENT_MISMATCH)echo "[Erro] Os dados no disco de destino não correspondem ao mapa de recuperação, então provavelmente é outro disco físico. Retomada recusada. Escolha NEW para recomeçar." ;;
    ERR_REPAIR)     echo "⚠ O diskutil repairDisk relatou um erro no disco de destino. A tabela de partições pode estar danificada." ;;
    DONE)           echo "Migração concluída com sucesso! O disco está pronto para uso." ;;
  esac
}

msg_zh() {
  case "$1" in
    TITLE)          echo "macOS 时间机器存储迁移与恢复工具" ;;
    ROOT_ERR)       echo "[错误] 必须以管理员身份运行此脚本。" ;;
    ROOT_HINT)      echo "请使用 sudo 运行：sudo %s" ;;
    STEP1)          echo "[1/6] 正在检查终端权限..." ;;
    FDA_ERR)        echo "[警告] 终端没有「完全磁盘访问权限」(Full Disk Access)。" ;;
    FDA_PATH)       echo "请前往：系统设置 -> 隐私与安全性 -> 完全磁盘访问权限" ;;
    FDA_ADD)        echo "添加并启用「终端」，然后重新运行脚本。" ;;
    FDA_OK)         echo "✓ 已确认可访问块设备。" ;;
    STEP2)          echo "[2/6] 已连接的存储设备：" ;;
    ASK_SRC)        echo "请输入源磁盘标识符（例如 disk1）：" ;;
    ASK_DST)        echo "请输入目标磁盘标识符（例如 disk5）：" ;;
    ERR_NOTFOUND)   echo "[错误] 未找到磁盘 %s！" ;;
    ERR_SAME)       echo "[严重错误] 源磁盘与目标磁盘相同！已取消。" ;;
    WARN_ERASE)     echo "警告：%s 上的所有数据将被彻底销毁！" ;;
    LBL_SRC)        echo "源磁盘：%s" ;;
    LBL_DST)        echo "目标磁盘：%s" ;;
    ASK_CONFIRM)    echo "您确定要继续吗？请输入 'YES' 以继续：" ;;
    CANCELLED)      echo "用户已取消操作。" ;;
    STEP3)          echo "[3/6] 正在检查 %s 是否存在坏扇区..." ;;
    SMART_FAIL)     echo "⚠ 磁盘 SMART 状态：FAILING（严重硬件故障）。" ;;
    QUICK_READ)     echo "正在读取磁盘的多个位置以检查完整性..." ;;
    IO_ERR)         echo "⚠ 读取磁盘时检测到 I/O 错误！" ;;
    READ_OK)        echo "✓ 所有抽查位置的读取测试均成功完成。" ;;
    STEP4)          echo "[4/6] 正在卸载磁盘以便安全克隆..." ;;
    STEP5)          echo "[5/6] 正在开始数据传输..." ;;
    USE_RESCUE)     echo "磁盘存在错误。将使用带恢复映射文件的 GNU ddrescue。" ;;
    DDRESCUE_MISSING) echo "未找到 ddrescue。正在通过 Homebrew 安装..." ;;
    BREW_ERR)       echo "[错误] 缺少 ddrescue，且无法自动安装。请以普通用户身份（不要使用 sudo）运行 'brew install ddrescue'，然后重新运行脚本。" ;;
    MAP_SAVED)      echo "进度映射文件将保存到：%s" ;;
    RUN_RESCUE)     echo "正在运行 ddrescue..." ;;
    USE_DD)         echo "磁盘状态良好。将使用 dd 进行标准块克隆。" ;;
    RUN_DD)         echo "正在运行 dd（块大小 64M）..." ;;
    STEP6)          echo "[6/6] 正在修复分区表并扩展 APFS 容器..." ;;
    APFS_FOUND)     echo "已找到 APFS 分区：/dev/%s" ;;
    RESIZING)       echo "正在将 APFS 容器扩展到新磁盘的全部容量..." ;;
    RESIZED)        echo "✓ APFS 容器已扩展到最大容量。" ;;
    APFS_NOTFOUND)  echo "[警告] 未能自动检测到 APFS 分区。" ;;
    CHECK_MANUAL)   echo "请手动检查分区布局：diskutil list %s" ;;
    ERR_SIZEUNK)    echo "[错误] 无法确定源磁盘或目标磁盘的大小。已取消。" ;;
    ERR_SIZE)       echo "[错误] 目标磁盘（%s GB）小于源磁盘（%s GB）。已取消。" ;;
    DD_FAILED)      echo "⚠ dd 在传输过程中失败。正在切换到 ddrescue 以完成复制。" ;;
    VERIFYING)      echo "正在验证卷 %s..." ;;
    UNLOCK)         echo "卷 %s 已锁定。请在提示时输入其密码：" ;;
    VERIFY_OK)      echo "✓ 所有卷均通过验证。" ;;
    VERIFY_FAIL)    echo "⚠ 部分卷无法验证。请手动运行 'diskutil verifyVolume'，并在使用该磁盘前确认时间机器中的备份历史记录。" ;;
    ERR_WHOLE)      echo "[错误] %s 不是完整的物理磁盘。请使用整盘（例如 disk2），不要使用分区（例如 disk2s2）。" ;;
    ERR_VIRTUAL)    echo "[错误] %s 是虚拟 APFS 容器，不是物理磁盘。请使用物理磁盘的标识符。" ;;
    ERR_SYSDISK)    echo "[严重错误] %s 包含正在运行的系统。拒绝继续。" ;;
    ERR_SYSUNK)     echo "[严重错误] 无法可靠地确定哪些物理磁盘包含正在运行的系统。拒绝继续。" ;;
    ERR_UNMOUNT)    echo "[错误] 无法卸载 %s。请关闭所有正在使用它的程序后重试。尚未写入任何数据。" ;;
    MAP_EXISTS)     echo "这对磁盘已存在对应的恢复映射文件：%s" ;;
    ASK_RESUME)     echo "输入 RESUME 以继续被中断的迁移，或输入 NEW 重新开始（旧映射文件将被归档）：" ;;
    MAP_MISMATCH)   echo "[错误] 恢复映射文件 %s 不属于这对磁盘。请移走该文件后重试。" ;;
    RESCUE_CLEAN)   echo "✓ ddrescue 已成功读取所有数据块。" ;;
    RESCUE_LOSS)    echo "⚠ ddrescue 无法恢复 %s 字节。这些区域中的文件可能已损坏。映射文件：%s" ;;
    ERR_COPY)       echo "[错误] 复制未完成。请使用相同的磁盘重新运行脚本，以便根据恢复映射文件继续。" ;;
    ERR_RESIZE)     echo "[错误] 无法扩展 APFS 容器。" ;;
    NO_VOLUMES)     echo "⚠ 在新容器中未找到任何 APFS 卷。" ;;
    WARN_PARTIAL_TARGET)echo "⚠ 目标磁盘可能已被部分覆盖，目前还不能使用。" ;;
    HIST_HINT)      echo "擦除旧磁盘之前，请确认备份历史：在「系统设置 -> 通用 -> 时间机器」中添加新磁盘并打开「浏览时间机器备份」，或运行 'tmutil listbackups'。" ;;
    DONE_PARTIAL)   echo "迁移已完成，但带有警告：部分数据无法恢复或验证。请勿擦除源磁盘。" ;;
    DONE_FAILED)    echo "迁移失败。请勿擦除源磁盘。请查看上方的消息。" ;;
    ERR_NOAPFS)     echo "[错误] %s 不包含 APFS 容器。TimeWarp 只迁移使用 APFS 的时间机器磁盘。已取消。" ;;
    MAP_CONTENT_MISMATCH)echo "[错误] 目标磁盘上的数据与恢复映射文件不一致，很可能是另一块物理磁盘。拒绝继续。请选择 NEW 重新开始。" ;;
    ERR_REPAIR)     echo "⚠ diskutil repairDisk 在目标磁盘上报告了错误。分区表可能已损坏。" ;;
    DONE)           echo "迁移成功完成！磁盘已可使用。" ;;
  esac
}

# t KEY -> translated string (falls back to English)
t() {
  local out
  out="$("msg_${TW_LANG}" "$1")"
  if [ -z "$out" ]; then
    out="$(msg_en "$1")"
  fi
  printf '%s' "$out"
}

# say COLOR KEY [args...] -> colored, translated line
say() {
  local color="$1" key="$2" fmt
  shift 2
  fmt="$(t "$key")"
  # shellcheck disable=SC2059
  printf "${color}${fmt}${NC}\n" "$@"
}

# ask COLOR KEY VAR -> prompt with translated text
ask() {
  local prompt
  prompt="$(t "$2")"
  read -rp "$prompt" "$3"
}

# ------------------------------------------------------------------------------
# Language selection (English by default)
# Override without a prompt: TIMEWARP_LANG=ru sudo -E ./timewarp.sh
# ------------------------------------------------------------------------------
TW_LANG="en"

select_language() {
  if [ -n "${TIMEWARP_LANG:-}" ]; then
    case "$TIMEWARP_LANG" in
      en|ru|es|de|fr|pt|zh) TW_LANG="$TIMEWARP_LANG" ;;
    esac
    return
  fi

  clear
  echo "Select language / Выберите язык / Elige idioma / Sprache wählen / Choisir la langue / Escolha o idioma / 选择语言"
  echo "  1) English (default)"
  echo "  2) Русский"
  echo "  3) Español"
  echo "  4) Deutsch"
  echo "  5) Français"
  echo "  6) Português"
  echo "  7) 中文"
  read -rp "[1-7, Enter = 1]: " LANG_CHOICE
  case "${LANG_CHOICE:-1}" in
    2) TW_LANG="ru" ;;
    3) TW_LANG="es" ;;
    4) TW_LANG="de" ;;
    5) TW_LANG="fr" ;;
    6) TW_LANG="pt" ;;
    7) TW_LANG="zh" ;;
    *) TW_LANG="en" ;;
  esac
}

# plist_get TARGET KEYPATH -> value from `diskutil info -plist` (empty if missing)
plist_get() {
  diskutil info -plist "$1" 2>/dev/null | plutil -extract "$2" raw -o - - 2>/dev/null || true
}

# plist_list TARGET KEYPATH -> value from `diskutil list -plist` (empty if missing)
plist_list() {
  diskutil list -plist "$1" 2>/dev/null | plutil -extract "$2" raw -o - - 2>/dev/null || true
}

# disk_bytes /dev/diskN -> size in bytes (empty if unknown)
disk_bytes() {
  local b
  b="$(plist_get "$1" TotalSize)"
  if [ -z "$b" ]; then
    b="$(plist_get "$1" Size)"
  fi
  echo "$b"
}

# validate_disk ID -> succeeds only for whole-disk names like disk2 or /dev/disk2
validate_disk() {
  local id num
  id="${1#/dev/}"
  num="${id#disk}"
  case "$id" in
    disk*) ;;
    *) return 1 ;;
  esac
  case "$num" in
    ''|*[!0-9]*) return 1 ;;
  esac
  return 0
}

# has_apfs /dev/diskN -> succeeds if the disk contains an Apple_APFS partition
has_apfs() {
  local i=0 c
  while c="$(plist_list "$1" "AllDisksAndPartitions.0.Partitions.$i.Content")" && [ -n "$c" ]; do
    if [ "$c" = "Apple_APFS" ]; then
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

# Fingerprints are computed ONCE, before anything is written. The target UUID is
# deliberately excluded: cloning overwrites it with the source's UUID. Two identical
# drives can share these values, so resuming also verifies the DATA (map_samples_match).
src_fp() {
  echo "$(plist_get "$1" DiskUUID)|$(plist_get "$1" MediaName)|$(disk_bytes "$1")"
}
dst_fp() {
  echo "$(plist_get "$1" MediaName)|$(disk_bytes "$1")|$(plist_get "$1" BusProtocol)|$(plist_get "$1" IORegistryEntryName)"
}

# sys_disks -> whole-disk ids holding the running system, one per line.
# Fails (non-zero) whenever the answer cannot be established reliably.
sys_disks() {
  local mp whole phys i found out=""
  for mp in / /System/Volumes/Data; do
    whole="$(plist_get "$mp" ParentWholeDisk)"
    if [ -z "$whole" ]; then
      if [ "$mp" = "/" ]; then
        return 1
      fi
      continue
    fi
    out="$out$whole"$'\n'
    i=0
    found=0
    while phys="$(plist_get "$whole" "APFSPhysicalStores.$i.APFSPhysicalStore")" && [ -n "$phys" ]; do
      out="$out${phys%s[0-9]*}"$'\n'
      found=1
      i=$((i + 1))
    done
    if [ "$found" -eq 0 ] && [ "$(plist_get "$whole" VirtualOrPhysical)" = "Virtual" ]; then
      return 1
    fi
  done
  if [ -z "$out" ]; then
    return 1
  fi
  printf '%s' "$out"
  return 0
}

# map_unrecovered MAPFILE -> number of bytes not marked as finished (+)
map_unrecovered() {
  local f="$1" first=1 a b c total=0
  while read -r a b c; do
    case "$a" in
      ''|'#'*) continue ;;
    esac
    if [ "$first" -eq 1 ]; then
      first=0
      continue
    fi
    if [ "$c" != "+" ]; then
      total=$((total + b))
    fi
  done < "$f"
  echo "$total"
}

# sample_read DEV SKIP_SECTORS SECTORS OUTFILE -> succeeds only if dd exits cleanly
# AND exactly SECTORS*512 bytes were read.
sample_read() {
  local got
  dd if="$1" of="$4" bs=512 skip="$2" count="$3" 2>/dev/null || return 1
  got="$(wc -c < "$4" 2>/dev/null | tr -d ' ')"
  [ "$got" = "$(( $3 * 512 ))" ] || return 1
  return 0
}

# sample_equal SRC DST SKIP SECTORS TMPDIR -> succeeds only if BOTH reads succeed in
# full and the data is identical. Any read error counts as "different".
# Sets NONZERO_SEEN=1 when an identical sample contained at least one non-zero byte
# (identical all-zero areas prove nothing: a blank target looks the same).
sample_equal() {
  sample_read "$1" "$3" "$4" "$5/a" || return 1
  sample_read "$2" "$3" "$4" "$5/b" || return 1
  cmp -s "$5/a" "$5/b" || return 1
  if [ -n "$(LC_ALL=C tr -d '\000' < "$5/a" 2>/dev/null | head -c 1)" ]; then
    NONZERO_SEEN=1
  fi
  return 0
}

# extent_windows POS SIZE -> prints "skip_sectors sector_count" lines to compare.
# Extents up to 8 MiB are compared completely. Larger ones are sampled at
# 3 + SIZE/128MiB (max 32) evenly spread 64 KiB windows, always including the very
# start and the very end of the extent.
extent_windows() {
  local pos="$1" size="$2" len=65536 n k off sectors
  if [ "$size" -le 8388608 ]; then
    sectors=$((size / 512))
    if [ "$sectors" -ge 1 ]; then
      echo "$((pos / 512)) $sectors"
    fi
    return 0
  fi
  n=$((3 + size / 134217728))
  if [ "$n" -gt 32 ]; then
    n=32
  fi
  k=0
  while [ "$k" -lt "$n" ]; do
    off=$((pos + (size - len) * k / (n - 1)))
    echo "$((off / 512)) $((len / 512))"
    k=$((k + 1))
  done
  return 0
}

# map_samples_match MAPFILE SRC DST -> succeeds only if the data of up to 8 finished
# extents of the map is identical on source and target (see extent_windows).
# Fails closed: unreadable devices, short reads, no verifiable window, or nothing but
# zeros all count as failure.
# This is a PROBABILISTIC check. It makes reusing a map on the wrong drive unlikely, but
# only a full comparison of all finished areas, or a trustworthy hardware identity,
# would prove it.
map_samples_match() {
  local map="$1" src="$2" dst="$3" tmpd pass first a b c total=0 idx step=1 extents=0
  local windows skip sectors compared=0
  NONZERO_SEEN=0
  tmpd="$(mktemp -d)" || return 1
  if [ -z "$tmpd" ] || [ ! -d "$tmpd" ]; then
    return 1
  fi
  for pass in 1 2; do
    first=1
    idx=0
    while read -r a b c; do
      case "$a" in
        ''|'#'*) continue ;;
      esac
      if [ "$first" -eq 1 ]; then
        first=0
        continue
      fi
      if [ "$c" != "+" ]; then
        continue
      fi
      if [ "$pass" -eq 1 ]; then
        total=$((total + 1))
        continue
      fi
      idx=$((idx + 1))
      if [ "$extents" -lt 8 ] && [ $(( (idx - 1) % step )) -eq 0 ]; then
        extents=$((extents + 1))
        windows="$(extent_windows "$((a))" "$((b))")"
        while read -r skip sectors; do
          if [ -z "$sectors" ]; then
            continue
          fi
          if ! sample_equal "$src" "$dst" "$skip" "$sectors" "$tmpd"; then
            rm -rf "$tmpd"
            return 1
          fi
          compared=$((compared + 1))
        done <<< "$windows"
      fi
    done < "$map"
    if [ "$pass" -eq 1 ]; then
      if [ "$total" -eq 0 ]; then
        rm -rf "$tmpd"
        return 0
      fi
      step=$((total / 8 + 1))
    fi
  done
  rm -rf "$tmpd"
  # finished extents exist, but nothing was verified or only zeros matched
  if [ "$compared" -eq 0 ] || [ "$NONZERO_SEEN" -ne 1 ]; then
    return 1
  fi
  return 0
}

# dd_supports_progress -> succeeds if this dd accepts status=progress
# (older macOS releases may not; an unsupported option must not look like a copy failure)
dd_supports_progress() {
  dd if=/dev/zero of=/dev/null bs=512 count=1 status=progress >/dev/null 2>&1
}

# Real (non-root) user's home, even when running under sudo
REAL_USER="${SUDO_USER:-$(id -un)}"
REAL_HOME="$(dscl . -read "/Users/$REAL_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
if [ -z "$REAL_HOME" ] || [ ! -d "$REAL_HOME" ]; then
  REAL_HOME="$HOME"
fi

# Homebrew refuses to run as root, so install as the invoking user
install_ddrescue() {
  local brew_bin="" p
  for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$p" ]; then
      brew_bin="$p"
      break
    fi
  done
  if [ -n "$brew_bin" ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    sudo -u "$SUDO_USER" "$brew_bin" install ddrescue || true
  fi
  if ! command -v ddrescue >/dev/null 2>&1; then
    say "$RED" BREW_ERR
    exit 1
  fi
}

# run_rescue: one recovery map per disk pair (fingerprint taken before any write).
# Resuming requires an explicit RESUME and a data check against the target.
# Returns 0 on success (RESULT may become PARTIAL), 1 on failure.
# Declining to continue exits with 130 (never reported as success).
run_rescue() {
  local key meta answer lost
  if ! command -v ddrescue >/dev/null 2>&1; then
    say "$YELLOW" DDRESCUE_MISSING
    install_ddrescue
  fi

  key="$(printf '%s' "$MIGRATION_FP" | shasum -a 256 | cut -c1-12)"
  RESCUE_MAP="$REAL_HOME/Desktop/timewarp-$key.map"
  meta="$RESCUE_MAP.meta"

  if [ -f "$RESCUE_MAP" ]; then
    if [ ! -f "$meta" ] || [ "$(cat "$meta")" != "$MIGRATION_FP" ]; then
      say "$RED" MAP_MISMATCH "$RESCUE_MAP"
      return 1
    fi
    say "$YELLOW" MAP_EXISTS "$RESCUE_MAP"
    ask "$NC" ASK_RESUME answer
    case "$answer" in
      RESUME)
        if ! map_samples_match "$RESCUE_MAP" "$SRC_RDISK" "$DST_RDISK"; then
          say "$RED" MAP_CONTENT_MISMATCH
          return 1
        fi
        ;;
      NEW)
        mv "$RESCUE_MAP" "$RESCUE_MAP.old-$(date +%Y%m%d%H%M%S)"
        printf '%s\n' "$MIGRATION_FP" > "$meta"
        ;;
      *)
        say "$NC" CANCELLED
        if [ "$DD_STARTED" -eq 1 ]; then
          say "$RED" WARN_PARTIAL_TARGET
        fi
        exit 130
        ;;
    esac
  else
    printf '%s\n' "$MIGRATION_FP" > "$meta"
  fi

  say "$NC" MAP_SAVED "$RESCUE_MAP"
  say "$NC" RUN_RESCUE
  if ! ddrescue -f -n "$SRC_RDISK" "$DST_RDISK" "$RESCUE_MAP"; then
    return 1
  fi

  lost="$(map_unrecovered "$RESCUE_MAP")"
  if [ "$lost" -gt 0 ]; then
    say "$YELLOW" RESCUE_LOSS "$lost" "$RESCUE_MAP"
    RESULT="PARTIAL"
  else
    say "$GREEN" RESCUE_CLEAN
  fi
  return 0
}

DD_STARTED=0
select_language

clear
echo -e "${BLUE}=================================================================${NC}"
say "$BLUE" TITLE
echo -e "${BLUE}=================================================================${NC}\n"

# 1. Root check
if [ "$EUID" -ne 0 ] && [ "${TIMEWARP_SELFTEST:-0}" != "1" ]; then
  say "$RED" ROOT_ERR
  say "$NC" ROOT_HINT "$0"
  exit 1
fi

# 2. Full Disk Access check (TCC/SIP)
say "$YELLOW" STEP1
FIRST_DISK="$(diskutil list | awk '/^\/dev\/disk[0-9]+/ { print $1; exit }')"
FIRST_DISK="${FIRST_DISK:-/dev/disk0}"
if [ "${TIMEWARP_SKIP_FDA:-0}" != "1" ] && [ "${TIMEWARP_SELFTEST:-0}" != "1" ] \
  && ! dd if="/dev/r${FIRST_DISK#/dev/}" of=/dev/null bs=512 count=1 >/dev/null 2>&1; then
  say "$RED" FDA_ERR
  say "$NC" FDA_PATH
  say "$NC" FDA_ADD
  exit 1
fi
say "$GREEN" FDA_OK
echo ""

# 3. Interactive source / target selection
say "$YELLOW" STEP2
diskutil list
echo ""

ask "$NC" ASK_SRC SRC_INPUT
if ! validate_disk "$SRC_INPUT"; then
  say "$RED" ERR_WHOLE "$SRC_INPUT"
  exit 1
fi
SRC_DISK="/dev/${SRC_INPUT#/dev/}"
SRC_RDISK="/dev/r${SRC_INPUT#/dev/}"

if [ "${TIMEWARP_SELFTEST:-0}" != "1" ] && [ ! -b "$SRC_DISK" ]; then
  say "$RED" ERR_NOTFOUND "$SRC_DISK"
  exit 1
fi

ask "$NC" ASK_DST DST_INPUT
if ! validate_disk "$DST_INPUT"; then
  say "$RED" ERR_WHOLE "$DST_INPUT"
  exit 1
fi
DST_DISK="/dev/${DST_INPUT#/dev/}"
DST_RDISK="/dev/r${DST_INPUT#/dev/}"

if [ "${TIMEWARP_SELFTEST:-0}" != "1" ] && [ ! -b "$DST_DISK" ]; then
  say "$RED" ERR_NOTFOUND "$DST_DISK"
  exit 1
fi

if [ "$SRC_DISK" = "$DST_DISK" ]; then
  say "$RED" ERR_SAME
  exit 1
fi

# Both must be whole physical disks (structured diskutil data, fail closed)
for D in "$SRC_DISK" "$DST_DISK"; do
  if [ "$(plist_get "$D" WholeDisk)" != "true" ]; then
    say "$RED" ERR_WHOLE "$D"
    exit 1
  fi
  # A synthesized APFS container lists its physical stores. (VirtualOrPhysical is no
  # use here: disk images report "Virtual" although they are ordinary whole disks.)
  if [ -n "$(plist_get "$D" APFSPhysicalStores.0.APFSPhysicalStore)" ]; then
    say "$RED" ERR_VIRTUAL "$D"
    exit 1
  fi
done

# The source must really contain APFS - checked before the target is ever touched
if ! has_apfs "$SRC_DISK"; then
  say "$RED" ERR_NOAPFS "$SRC_DISK"
  exit 1
fi

# Neither disk may hold the running system. If this cannot be established
# reliably, refuse to continue.
if ! SYS_LIST="$(sys_disks)" || [ -z "$SYS_LIST" ]; then
  say "$RED" ERR_SYSUNK
  exit 1
fi
for SD in $SYS_LIST; do
  if [ "/dev/$SD" = "$DST_DISK" ] || [ "/dev/$SD" = "$SRC_DISK" ]; then
    say "$RED" ERR_SYSDISK "/dev/$SD"
    exit 1
  fi
done

# Target must be at least as large as the source
SRC_BYTES="$(disk_bytes "$SRC_DISK")"
DST_BYTES="$(disk_bytes "$DST_DISK")"
case "$SRC_BYTES$DST_BYTES" in
  ''|*[!0-9]*) say "$RED" ERR_SIZEUNK; exit 1 ;;
esac
if [ -z "$SRC_BYTES" ] || [ -z "$DST_BYTES" ]; then
  say "$RED" ERR_SIZEUNK
  exit 1
fi
if [ "$DST_BYTES" -lt "$SRC_BYTES" ]; then
  say "$RED" ERR_SIZE "$((DST_BYTES / 1000000000))" "$((SRC_BYTES / 1000000000))"
  exit 1
fi

echo ""
say "$YELLOW" WARN_ERASE "$DST_DISK"
say "$NC" LBL_SRC "$SRC_DISK"
say "$NC" LBL_DST "$DST_DISK"
ask "$NC" ASK_CONFIRM CONFIRM
if [ "$CONFIRM" != "YES" ]; then
  say "$NC" CANCELLED
  exit 130
fi

# Identity of this exact disk pair, taken before anything is written
MIGRATION_FP="$(src_fp "$SRC_DISK")>>$(dst_fp "$DST_DISK")"

# 4. Bad sector diagnostics (before the transfer)
echo ""
say "$YELLOW" STEP3 "$SRC_DISK"
HAS_BAD_SECTORS=0

SMART_STATUS=$(diskutil info "$SRC_DISK" | grep "SMART Status" | awk -F: '{print $2}' | tr -d ' ' || true)
if [ "$SMART_STATUS" = "Failing" ]; then
  say "$RED" SMART_FAIL
  HAS_BAD_SECTORS=1
fi

say "$NC" QUICK_READ
# Read 256 MB at 5 positions across the disk (start, 25%, 50%, 75%, end)
TOTAL_MB=$((SRC_BYTES / 1048576))
MAX_OFF=$((TOTAL_MB - 256))
if [ "$MAX_OFF" -lt 0 ]; then
  MAX_OFF=0
fi
READ_FAILED=0
for PCT in 0 25 50 75 100; do
  OFF=$((TOTAL_MB * PCT / 100))
  if [ "$OFF" -gt "$MAX_OFF" ]; then
    OFF=$MAX_OFF
  fi
  if ! dd if="$SRC_RDISK" of=/dev/null bs=1m skip="$OFF" count=256 >/dev/null 2>&1; then
    READ_FAILED=1
  fi
done
if [ "$READ_FAILED" -eq 1 ]; then
  say "$RED" IO_ERR
  HAS_BAD_SECTORS=1
else
  say "$GREEN" READ_OK
fi

# Test hook: force the ddrescue path (used by tests/migration_test.sh)
if [ "${TIMEWARP_FORCE_RESCUE:-0}" = "1" ]; then
  HAS_BAD_SECTORS=1
fi

# 5. Unmount (abort if either disk cannot be unmounted - nothing is written yet)
echo ""
say "$YELLOW" STEP4
for D in "$SRC_DISK" "$DST_DISK"; do
  if ! diskutil unmountDisk "$D"; then
    say "$RED" ERR_UNMOUNT "$D"
    exit 1
  fi
done

# 6. Clone (tool chosen by disk health; dd falls back to ddrescue on failure)
RESULT="SUCCESS"
echo ""
say "$YELLOW" STEP5

if [ "$HAS_BAD_SECTORS" -eq 1 ]; then
  say "$RED" USE_RESCUE
  if ! run_rescue; then
    RESULT="FAILED"
  fi
else
  say "$GREEN" USE_DD
  say "$NC" RUN_DD
  DD_STARTED=1
  DD_EXTRA=()
  if dd_supports_progress; then
    DD_EXTRA=(status=progress)
  fi
  if ! dd if="$SRC_RDISK" of="$DST_RDISK" bs=64m "${DD_EXTRA[@]}"; then
    say "$RED" DD_FAILED
    if ! run_rescue; then
      RESULT="FAILED"
    fi
  fi
fi

if [ "$RESULT" = "FAILED" ]; then
  say "$RED" ERR_COPY
  echo ""
  say "$RED" DONE_FAILED
  exit 1
fi

# 7. Repair partition table and expand the APFS container
echo ""
say "$YELLOW" STEP6
sleep 3
if ! diskutil repairDisk "$DST_DISK"; then
  say "$YELLOW" ERR_REPAIR
  if [ "$RESULT" = "SUCCESS" ]; then
    RESULT="PARTIAL"
  fi
fi

APFS_PART=$(diskutil list "$DST_DISK" | grep "Apple_APFS" | awk '{print $NF}' | head -n 1)

if [ -n "$APFS_PART" ]; then
  say "$GREEN" APFS_FOUND "$APFS_PART"
  say "$NC" RESIZING
  if diskutil apfs resizeContainer "$APFS_PART" 0; then
    say "$GREEN" RESIZED
  else
    say "$RED" ERR_RESIZE
    RESULT="FAILED"
  fi

  # 8. Verify the volumes of the new container (unlock encrypted ones first)
  CONTAINER=$(diskutil apfs list | awk -v part="$APFS_PART" '
    /Container disk[0-9]+/ { c = $3 }
    /Physical Store/ && index($0, part) { print c; exit }')
  VERIFY_BAD=0
  VOLS=""
  if [ -n "$CONTAINER" ]; then
    VOLS=$(diskutil list "$CONTAINER" | grep "APFS Volume" | awk '{print $NF}' || true)
  fi
  if [ -z "$VOLS" ]; then
    say "$YELLOW" NO_VOLUMES
    VERIFY_BAD=1
  else
    for VOL in $VOLS; do
      say "$NC" VERIFYING "$VOL"
      if diskutil info "$VOL" | grep -Eq "Locked: +Yes"; then
        say "$YELLOW" UNLOCK "$VOL"
        if ! diskutil apfs unlockVolume "$VOL"; then
          VERIFY_BAD=1
          continue
        fi
      fi
      diskutil verifyVolume "$VOL" || VERIFY_BAD=1
    done
  fi
  if [ "$VERIFY_BAD" -eq 0 ]; then
    say "$GREEN" VERIFY_OK
  else
    say "$YELLOW" VERIFY_FAIL
    if [ "$RESULT" = "SUCCESS" ]; then
      RESULT="PARTIAL"
    fi
  fi
else
  say "$YELLOW" APFS_NOTFOUND
  say "$NC" CHECK_MANUAL "$DST_DISK"
  RESULT="FAILED"
fi

echo ""
case "$RESULT" in
  SUCCESS)
    echo -e "${GREEN}=================================================================${NC}"
    say "$GREEN" DONE
    say "$NC" HIST_HINT
    echo -e "${GREEN}=================================================================${NC}"
    exit 0
    ;;
  PARTIAL)
    echo -e "${YELLOW}=================================================================${NC}"
    say "$YELLOW" DONE_PARTIAL
    say "$NC" HIST_HINT
    echo -e "${YELLOW}=================================================================${NC}"
    exit 2
    ;;
  *)
    echo -e "${RED}=================================================================${NC}"
    say "$RED" DONE_FAILED
    echo -e "${RED}=================================================================${NC}"
    exit 1
    ;;
esac
