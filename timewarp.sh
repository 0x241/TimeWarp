#!/usr/bin/env bash
# ==============================================================================
# macOS Time Machine Clone & Recovery Tool (APFS)
# Automated migration from failing/healthy drive to a new destination drive.
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

clear
echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}       macOS Time Machine Storage Migration & Recovery Tool       ${NC}"
echo -e "${BLUE}=================================================================${NC}\n"

# 1. Проверка прав root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[Ошибка] Скрипт должен быть запущен с правами администратора.${NC}"
  echo "Запустите команду через sudo: sudo $0"
  exit 1
fi

# 2. Проверка Full Disk Access (TCC/SIP)
echo -e "${YELLOW}[1/6] Проверка системных разрешений Terminal...${NC}"
if ! ls /dev/rdisk0 >/dev/null 2>&1; then
  echo -e "${RED}[Внимание] У Терминала нет 'Полного доступа к диску' (Full Disk Access).${NC}"
  echo "Перейдите в: Системные настройки -> Конфиденциальность и безопасность -> Полный доступ к диску"
  echo "Добавьте и включите Terminal, затем перезапустите скрипт."
  exit 1
fi
echo -e "${GREEN}✓ Разрешения доступа к блочным устройствам подтверждены.${NC}\n"

# 3. Интерактивный выбор исходного и целевого дисков
echo -e "${YELLOW}[2/6] Список подключенных накопителей:${NC}"
diskutil list
echo ""

read -rp "Введите идентификатор ИСХОДНОГО диска (например, disk1): " SRC_INPUT
SRC_DISK="/dev/${SRC_INPUT#/dev/}"
SRC_RDISK="/dev/r${SRC_INPUT#/dev/}"

if [ ! -b "$SRC_DISK" ]; then
  echo -e "${RED}[Ошибка] Диск $SRC_DISK не найден!${NC}"
  exit 1
fi

read -rp "Введите идентификатор ЦЕЛЕВОГО диска (например, disk5): " DST_INPUT
DST_DISK="/dev/${DST_INPUT#/dev/}"
DST_RDISK="/dev/r${DST_INPUT#/dev/}"

if [ ! -b "$DST_DISK" ]; then
  echo -e "${RED}[Ошибка] Диск $DST_DISK не найден!${NC}"
  exit 1
fi

if [ "$SRC_DISK" == "$DST_DISK" ]; then
  echo -e "${RED}[Критическая ошибка] Исходный и целевой диск совпадают! Отмена.${NC}"
  exit 1
fi

echo -e "\n${YELLOW}ВНИМАНИЕ: Все данные на $DST_DISK будут ПОЛНОСТЬЮ УНИЧТОЖЕНЫ!${NC}"
echo "Источник: $SRC_DISK"
echo "Приемник: $DST_DISK"
read -rp "Вы абсолютно уверены? Введите 'YES' для продолжения: " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
  echo "Операция отменена пользователем."
  exit 0
fi

# 4. Диагностика диска на наличие сбойных секторов
echo -e "\n${YELLOW}[3/6] Проверка накопителя $SRC_DISK на наличие сбойных секторов...${NC}"
HAS_BAD_SECTORS=0

# Проверка SMART через diskutil (если поддерживается)
SMART_STATUS=$(diskutil info "$SRC_DISK" | grep "SMART Status" | awk -F: '{print $2}' | tr -d ' ' || true)
if [ "$SMART_STATUS" == "Failing" ]; then
  echo -e "${RED}⚠ SMART статус диска: FAILING (критические аппаратные сбои).${NC}"
  HAS_BAD_SECTORS=1
fi

# Тестовое чтение начальных 2 ГБ для обнаружения I/O ошибок
echo "Выполняется быстрый срез чтения для проверки целостности..."
if ! dd if="$SRC_RDISK" of=/dev/null bs=1M count=2048 status=none 2>/dev/null; then
  echo -e "${RED}⚠ Обнаружены ошибки ввода-вывода (I/O Errors) при чтении секций!${NC}"
  HAS_BAD_SECTORS=1
else
  echo -e "${GREEN}✓ Первичный тест чтения завершен успешно.${NC}"
fi

# 5. Размонтирование разделов перед клонированием
echo -e "\n${YELLOW}[4/6] Размонтирование дисков для безопасного клонирования...${NC}"
diskutil unmountDisk "$SRC_DISK" || true
diskutil unmountDisk "$DST_DISK" || true

# 6. Клонирование (Выбор инструмента)
echo -e "\n${YELLOW}[5/6] Запуск процесса переноса данных...${NC}"

if [ "$HAS_BAD_SECTORS" -eq 1 ]; then
  echo -e "${RED}Диск содержит ошибки. Используется GNU ddrescue с картой восстановления.${NC}"
  
  # Проверка наличия ddrescue в системе
  if ! command -v ddrescue &>/dev/null; then
    echo -e "${YELLOW}Утилита ddrescue не найдена. Устанавливаем через Homebrew...${NC}"
    if command -v brew &>/dev/null; then
      brew install ddrescue
    else
      echo -e "${RED}[Ошибка] Homebrew не установлен. Установите 'ddrescue' вручную.${NC}"
      exit 1
    fi
  fi

  RESCUE_MAP="$HOME/Desktop/tm_migration_recovery.map"
  echo "Карта прогресса будет сохранена в: $RESCUE_MAP"
  echo "Запуск ddrescue..."
  ddrescue -f -n "$SRC_RDISK" "$DST_RDISK" "$RESCUE_MAP"
else
  echo -e "${GREEN}Диск в норме. Используется стандартный прямой блочный клон через dd.${NC}"
  echo "Запуск dd (размер блока 64M)..."
  dd if="$SRC_RDISK" of="$DST_RDISK" bs=64M status=progress
fi

# 7. Восстановление таблицы разделов и расширение контейнера APFS
echo -e "\n${YELLOW}[6/6] Проверка таблицы разделов и расширение контейнера APFS...${NC}"
sleep 3
diskutil repairDisk "$DST_DISK" || true

# Поиск APFS раздела на целевом диске
APFS_PART=$(diskutil list "$DST_DISK" | grep "Apple_APFS" | awk '{print $NF}' | head -n 1)

if [ -n "$APFS_PART" ]; then
  echo -e "Найден APFS раздел: ${GREEN}/dev/$APFS_PART${NC}"
  echo "Расширяем контейнер APFS на весь доступный объем нового накопителя..."
  diskutil apfs resizeContainer "$APFS_PART" 0
  echo -e "${GREEN}✓ Контейнер APFS успешно расширен на максимум.${NC}"
else
  echo -e "${YELLOW}[Предупреждение] APFS раздел не обнаружен автоматически.${NC}"
  echo "Проверьте разметку вручную через: diskutil list $DST_DISK"
fi

echo -e "\n${GREEN}=================================================================${NC}"
echo -e "${GREEN}   Миграция успешно завершена! Диск готов к использованию.        ${NC}"
echo -e "${GREEN}=================================================================${NC}"