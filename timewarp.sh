#!/usr/bin/env bash
# ==============================================================================
# TimeWarp - macOS Time Machine Clone & Recovery Tool (APFS)
# Automated migration from a failing/healthy drive to a new destination drive.
# Languages: en (default), ru, es, de, fr, pt, zh
# Compatible with the stock macOS bash 3.2.
# ==============================================================================

set -e

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
    QUICK_READ)     echo "Running a quick read test to verify integrity..." ;;
    IO_ERR)         echo "⚠ I/O errors detected while reading the disk!" ;;
    READ_OK)        echo "✓ Initial read test completed successfully." ;;
    STEP4)          echo "[4/6] Unmounting disks for safe cloning..." ;;
    STEP5)          echo "[5/6] Starting data transfer..." ;;
    USE_RESCUE)     echo "The disk has errors. Using GNU ddrescue with a recovery map." ;;
    DDRESCUE_MISSING) echo "ddrescue not found. Installing via Homebrew..." ;;
    BREW_ERR)       echo "[Error] Homebrew is not installed. Please install 'ddrescue' manually." ;;
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
    QUICK_READ)     echo "Выполняется быстрый тест чтения для проверки целостности..." ;;
    IO_ERR)         echo "⚠ Обнаружены ошибки ввода-вывода (I/O Errors) при чтении диска!" ;;
    READ_OK)        echo "✓ Первичный тест чтения завершён успешно." ;;
    STEP4)          echo "[4/6] Размонтирование дисков для безопасного клонирования..." ;;
    STEP5)          echo "[5/6] Запуск переноса данных..." ;;
    USE_RESCUE)     echo "Диск содержит ошибки. Используется GNU ddrescue с картой восстановления." ;;
    DDRESCUE_MISSING) echo "Утилита ddrescue не найдена. Устанавливаем через Homebrew..." ;;
    BREW_ERR)       echo "[Ошибка] Homebrew не установлен. Установите 'ddrescue' вручную." ;;
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
    QUICK_READ)     echo "Ejecutando una prueba de lectura rápida para verificar la integridad..." ;;
    IO_ERR)         echo "⚠ ¡Se detectaron errores de E/S al leer el disco!" ;;
    READ_OK)        echo "✓ La prueba de lectura inicial terminó correctamente." ;;
    STEP4)          echo "[4/6] Desmontando los discos para una clonación segura..." ;;
    STEP5)          echo "[5/6] Iniciando la transferencia de datos..." ;;
    USE_RESCUE)     echo "El disco tiene errores. Se usará GNU ddrescue con un mapa de recuperación." ;;
    DDRESCUE_MISSING) echo "No se encontró ddrescue. Instalando con Homebrew..." ;;
    BREW_ERR)       echo "[Error] Homebrew no está instalado. Instala 'ddrescue' manualmente." ;;
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
    QUICK_READ)     echo "Schneller Lesetest zur Integritätsprüfung läuft..." ;;
    IO_ERR)         echo "⚠ Beim Lesen der Festplatte wurden E/A-Fehler erkannt!" ;;
    READ_OK)        echo "✓ Erster Lesetest erfolgreich abgeschlossen." ;;
    STEP4)          echo "[4/6] Laufwerke werden für sicheres Klonen ausgehängt..." ;;
    STEP5)          echo "[5/6] Datenübertragung wird gestartet..." ;;
    USE_RESCUE)     echo "Die Festplatte hat Fehler. GNU ddrescue mit Wiederherstellungskarte wird verwendet." ;;
    DDRESCUE_MISSING) echo "ddrescue nicht gefunden. Installation über Homebrew..." ;;
    BREW_ERR)       echo "[Fehler] Homebrew ist nicht installiert. Bitte installiere 'ddrescue' manuell." ;;
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
    QUICK_READ)     echo "Exécution d'un test de lecture rapide pour vérifier l'intégrité..." ;;
    IO_ERR)         echo "⚠ Erreurs d'E/S détectées lors de la lecture du disque !" ;;
    READ_OK)        echo "✓ Le test de lecture initial s'est terminé avec succès." ;;
    STEP4)          echo "[4/6] Démontage des disques pour un clonage sûr..." ;;
    STEP5)          echo "[5/6] Lancement du transfert des données..." ;;
    USE_RESCUE)     echo "Le disque contient des erreurs. Utilisation de GNU ddrescue avec une carte de récupération." ;;
    DDRESCUE_MISSING) echo "ddrescue introuvable. Installation via Homebrew..." ;;
    BREW_ERR)       echo "[Erreur] Homebrew n'est pas installé. Installez 'ddrescue' manuellement." ;;
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
    QUICK_READ)     echo "Executando um teste rápido de leitura para verificar a integridade..." ;;
    IO_ERR)         echo "⚠ Erros de E/S detectados durante a leitura do disco!" ;;
    READ_OK)        echo "✓ O teste inicial de leitura foi concluído com sucesso." ;;
    STEP4)          echo "[4/6] Desmontando os discos para clonagem segura..." ;;
    STEP5)          echo "[5/6] Iniciando a transferência de dados..." ;;
    USE_RESCUE)     echo "O disco tem erros. Usando GNU ddrescue com mapa de recuperação." ;;
    DDRESCUE_MISSING) echo "ddrescue não encontrado. Instalando via Homebrew..." ;;
    BREW_ERR)       echo "[Erro] O Homebrew não está instalado. Instale o 'ddrescue' manualmente." ;;
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
    DONE)           echo "Migração concluída com sucesso! O disco está pronto para uso." ;;
  esac
}

msg_zh() {
  case "$1" in
    TITLE)          echo "macOS 时间机器存储迁移与恢复工具" ;;
    ROOT_ERR)       echo "[错误] 必须以管理员身份运行此脚本。" ;;
    ROOT_HINT)      echo "请使用 sudo 运行：sudo %s" ;;
    STEP1)          echo "[1/6] 正在检查终端权限..." ;;
    FDA_ERR)        echo "[警告] 终端没有“完全磁盘访问权限”(Full Disk Access)。" ;;
    FDA_PATH)       echo "请前往：系统设置 -> 隐私与安全性 -> 完全磁盘访问权限" ;;
    FDA_ADD)        echo "添加并启用“终端”，然后重新运行脚本。" ;;
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
    QUICK_READ)     echo "正在执行快速读取测试以检查完整性..." ;;
    IO_ERR)         echo "⚠ 读取磁盘时检测到 I/O 错误！" ;;
    READ_OK)        echo "✓ 初始读取测试成功完成。" ;;
    STEP4)          echo "[4/6] 正在卸载磁盘以便安全克隆..." ;;
    STEP5)          echo "[5/6] 正在开始数据传输..." ;;
    USE_RESCUE)     echo "磁盘存在错误。将使用带恢复映射文件的 GNU ddrescue。" ;;
    DDRESCUE_MISSING) echo "未找到 ddrescue。正在通过 Homebrew 安装..." ;;
    BREW_ERR)       echo "[错误] 未安装 Homebrew。请手动安装 'ddrescue'。" ;;
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

select_language

clear
echo -e "${BLUE}=================================================================${NC}"
say "$BLUE" TITLE
echo -e "${BLUE}=================================================================${NC}\n"

# 1. Root check
if [ "$EUID" -ne 0 ]; then
  say "$RED" ROOT_ERR
  say "$NC" ROOT_HINT "$0"
  exit 1
fi

# 2. Full Disk Access check (TCC/SIP)
say "$YELLOW" STEP1
if ! ls /dev/rdisk0 >/dev/null 2>&1; then
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
SRC_DISK="/dev/${SRC_INPUT#/dev/}"
SRC_RDISK="/dev/r${SRC_INPUT#/dev/}"

if [ ! -b "$SRC_DISK" ]; then
  say "$RED" ERR_NOTFOUND "$SRC_DISK"
  exit 1
fi

ask "$NC" ASK_DST DST_INPUT
DST_DISK="/dev/${DST_INPUT#/dev/}"
DST_RDISK="/dev/r${DST_INPUT#/dev/}"

if [ ! -b "$DST_DISK" ]; then
  say "$RED" ERR_NOTFOUND "$DST_DISK"
  exit 1
fi

if [ "$SRC_DISK" = "$DST_DISK" ]; then
  say "$RED" ERR_SAME
  exit 1
fi

echo ""
say "$YELLOW" WARN_ERASE "$DST_DISK"
say "$NC" LBL_SRC "$SRC_DISK"
say "$NC" LBL_DST "$DST_DISK"
ask "$NC" ASK_CONFIRM CONFIRM
if [ "$CONFIRM" != "YES" ]; then
  say "$NC" CANCELLED
  exit 0
fi

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
if ! dd if="$SRC_RDISK" of=/dev/null bs=1M count=2048 status=none 2>/dev/null; then
  say "$RED" IO_ERR
  HAS_BAD_SECTORS=1
else
  say "$GREEN" READ_OK
fi

# 5. Unmount
echo ""
say "$YELLOW" STEP4
diskutil unmountDisk "$SRC_DISK" || true
diskutil unmountDisk "$DST_DISK" || true

# 6. Clone (tool chosen by disk health)
echo ""
say "$YELLOW" STEP5

if [ "$HAS_BAD_SECTORS" -eq 1 ]; then
  say "$RED" USE_RESCUE

  if ! command -v ddrescue >/dev/null 2>&1; then
    say "$YELLOW" DDRESCUE_MISSING
    if command -v brew >/dev/null 2>&1; then
      brew install ddrescue
    else
      say "$RED" BREW_ERR
      exit 1
    fi
  fi

  RESCUE_MAP="$HOME/Desktop/tm_migration_recovery.map"
  say "$NC" MAP_SAVED "$RESCUE_MAP"
  say "$NC" RUN_RESCUE
  ddrescue -f -n "$SRC_RDISK" "$DST_RDISK" "$RESCUE_MAP"
else
  say "$GREEN" USE_DD
  say "$NC" RUN_DD
  dd if="$SRC_RDISK" of="$DST_RDISK" bs=64M status=progress
fi

# 7. Repair partition table and expand the APFS container
echo ""
say "$YELLOW" STEP6
sleep 3
diskutil repairDisk "$DST_DISK" || true

APFS_PART=$(diskutil list "$DST_DISK" | grep "Apple_APFS" | awk '{print $NF}' | head -n 1)

if [ -n "$APFS_PART" ]; then
  say "$GREEN" APFS_FOUND "$APFS_PART"
  say "$NC" RESIZING
  diskutil apfs resizeContainer "$APFS_PART" 0
  say "$GREEN" RESIZED
else
  say "$YELLOW" APFS_NOTFOUND
  say "$NC" CHECK_MANUAL "$DST_DISK"
fi

echo ""
echo -e "${GREEN}=================================================================${NC}"
say "$GREEN" DONE
echo -e "${GREEN}=================================================================${NC}"
