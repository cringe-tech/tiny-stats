import Foundation

/// Selectable UI language. `.system` follows the macOS preferred language.
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system, en, ru, fr, de, ko, ja, zh
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return Loc.t(.system)
        case .en: return "English"
        case .ru: return "Русский"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .ko: return "한국어"
        case .ja: return "日本語"
        case .zh: return "简体中文"
        }
    }

    /// Concrete language code, resolving `.system` against the OS preference.
    var code: String {
        switch self {
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            if preferred.hasPrefix("zh") { return "zh" }
            for language in AppLanguage.allCases where language != .system {
                if preferred.hasPrefix(language.rawValue) { return language.rawValue }
            }
            return "en"
        default:
            return rawValue
        }
    }
}

/// Every user-facing string key.
enum LocKey: String {
    case overview, history, sensors, settings, quit
    case general, menuBar, panels
    case preview, menuBarCells, cellsHint, inMenuBar, available, dropToAdd, tapToAdd
    case defaultSet, useDefault, show, cellsShow, iconValue, labelValue, valueOnly
    case metrics, metricsHint, active, hiddenNotCollected, dropToHide, dragToHide
    case processLists, showProcessLists, topProcesses, cpuSection, memorySection, diskSection
    case updates, refreshInterval, refreshHint, showHistoryTab, keepHistoryFor
    case temperatureUnit, system, nerdStats, nerdStatsHint
    case startup, launchAtLogin, keyboardShortcuts, switchTabs, openSettings, language, version
    case cpu, memory, network, disk, gpu, battery
    case download, upload, used, free, read, write, average
    case collectingProcesses, collectingHistory, readingSensors
    case charging, notCharging, cycles
    case fans, temperature, power, voltage, current
    case lastSpan, minutesShort, hourShort
    case donate
    case checkForUpdates, checkingUpdates, upToDate, updateAvailable, downloadUpdate
    case autoCheckUpdates, updateFailed
    case removeHint
    case reportIssue
    case diagnostics, exportLogs, revealLogs, logsHint
    case cellsHidden
    case lowPowerMode
}

/// Runtime localization. A global so views that re-render on a settings change pick up
/// the new language without threading a binding through every subview.
enum Loc {
    // Read and written only on the main actor (AppState / SwiftUI views).
    nonisolated(unsafe) static var language: AppLanguage = .system

    static func t(_ key: LocKey) -> String {
        let code = language.code
        return table[code]?[key] ?? table["en"]?[key] ?? key.rawValue
    }

    /// Localized string with one `%@` argument substituted.
    static func t(_ key: LocKey, _ arg: String) -> String {
        t(key).replacingOccurrences(of: "%@", with: arg)
    }

    private static let table: [String: [LocKey: String]] = [
        "en": [
            .overview: "Overview", .history: "History", .sensors: "Sensors",
            .settings: "Settings", .quit: "Quit",
            .general: "General", .menuBar: "Menu Bar", .panels: "Panels",
            .preview: "Preview", .menuBarCells: "Menu Bar Cells",
            .cellsHint: "Tap to add or remove · drag to reorder · up to 5",
            .inMenuBar: "In menu bar", .available: "Available",
            .dropToAdd: "Drop here to add", .tapToAdd: "Tap a metric below to add it",
            .defaultSet: "Default set", .useDefault: "Use default",
            .show: "Show", .cellsShow: "Cells show",
            .iconValue: "Icon + value", .labelValue: "Label + value", .valueOnly: "Value only",
            .metrics: "Metrics",
            .metricsHint: "Drag to reorder, or move to Hidden to stop collecting it. Applies to Overview and History.",
            .active: "Active", .hiddenNotCollected: "Hidden — not collected",
            .dropToHide: "Drop here to hide", .dragToHide: "Drag a metric to Hidden to stop collecting it",
            .processLists: "Process lists", .showProcessLists: "Show process lists",
            .topProcesses: "Top processes per section",
            .cpuSection: "CPU section", .memorySection: "Memory section", .diskSection: "Disk section",
            .updates: "Refresh rate", .refreshInterval: "Refresh interval",
            .refreshHint: "Polls 3× slower in Low Power Mode and 1.5× slower on battery.",
            .showHistoryTab: "Show History tab", .keepHistoryFor: "Keep history for",
            .temperatureUnit: "Temperature unit", .system: "System",
            .nerdStats: "Nerd stats", .nerdStatsHint: "Show voltage, current and the full sensor list.",
            .startup: "Startup", .launchAtLogin: "Launch at login",
            .keyboardShortcuts: "Keyboard shortcuts", .switchTabs: "Switch tabs",
            .openSettings: "Open settings", .language: "Language", .version: "Version",
            .cpu: "CPU", .memory: "Memory", .network: "Network", .disk: "Disk",
            .gpu: "GPU", .battery: "Battery",
            .download: "Download", .upload: "Upload", .used: "Used", .free: "free",
            .read: "Read", .write: "Write", .average: "Average",
            .collectingProcesses: "Collecting process data…",
            .collectingHistory: "Collecting history…", .readingSensors: "Reading sensors…",
            .charging: "Charging", .notCharging: "Plugged in, not charging", .cycles: "Cycles",
            .fans: "Fans", .temperature: "Temperature", .power: "Power",
            .voltage: "Voltage", .current: "Current",
            .lastSpan: "Last %@", .minutesShort: "min", .hourShort: "h",
            .donate: "Donate crypto",
            .reportIssue: "Report a bug or idea",
            .checkForUpdates: "Check for updates", .checkingUpdates: "Checking for updates…",
            .upToDate: "TinyStats is up to date", .updateAvailable: "Update available: %@",
            .downloadUpdate: "Download", .autoCheckUpdates: "Check for updates automatically",
            .updateFailed: "Couldn’t check for updates",
            .removeHint: "Drag a cell here to remove it",
            .diagnostics: "Diagnostics", .exportLogs: "Export Logs…", .revealLogs: "Show in Finder",
            .logsHint: "Logs record errors and crashes. Export them and attach to a bug report.",
            .cellsHidden: "%@ cell(s) hidden — not enough room beside the notch.",
            .lowPowerMode: "Low Power Mode",
        ],
        "ru": [
            .overview: "Обзор", .history: "История", .sensors: "Сенсоры",
            .settings: "Настройки", .quit: "Выход",
            .general: "Основные", .menuBar: "Строка меню", .panels: "Панели",
            .preview: "Предпросмотр", .menuBarCells: "Ячейки строки меню",
            .cellsHint: "Нажмите чтобы добавить/убрать · перетащите для порядка · до 5",
            .inMenuBar: "В строке меню", .available: "Доступные",
            .dropToAdd: "Отпустите, чтобы добавить", .tapToAdd: "Нажмите метрику ниже, чтобы добавить",
            .defaultSet: "Набор по умолчанию", .useDefault: "По умолчанию",
            .show: "Отображение", .cellsShow: "Ячейки показывают",
            .iconValue: "Значок + значение", .labelValue: "Подпись + значение", .valueOnly: "Только значение",
            .metrics: "Метрики",
            .metricsHint: "Перетащите для порядка или в «Скрытые», чтобы не собирать. Влияет на Обзор и Историю.",
            .active: "Активные", .hiddenNotCollected: "Скрытые — не собираются",
            .dropToHide: "Отпустите, чтобы скрыть", .dragToHide: "Перетащите метрику в «Скрытые», чтобы не собирать",
            .processLists: "Списки процессов", .showProcessLists: "Показывать списки процессов",
            .topProcesses: "Топ процессов в секции",
            .cpuSection: "Секция CPU", .memorySection: "Секция памяти", .diskSection: "Секция диска",
            .updates: "Частота обновления", .refreshInterval: "Интервал обновления",
            .refreshHint: "В режиме энергосбережения опрос в 3× реже, на батарее — в 1.5×.",
            .showHistoryTab: "Показывать вкладку «История»", .keepHistoryFor: "Хранить историю",
            .temperatureUnit: "Единица температуры", .system: "Система",
            .nerdStats: "Расширенные данные", .nerdStatsHint: "Показывать напряжение, ток и весь список сенсоров.",
            .startup: "Запуск", .launchAtLogin: "Запускать при входе",
            .keyboardShortcuts: "Горячие клавиши", .switchTabs: "Переключение вкладок",
            .openSettings: "Открыть настройки", .language: "Язык", .version: "Версия",
            .cpu: "CPU", .memory: "Память", .network: "Сеть", .disk: "Диск",
            .gpu: "GPU", .battery: "Батарея",
            .download: "Загрузка", .upload: "Отдача", .used: "Занято", .free: "свободно",
            .read: "Чтение", .write: "Запись", .average: "Среднее",
            .collectingProcesses: "Сбор данных о процессах…",
            .collectingHistory: "Сбор истории…", .readingSensors: "Чтение сенсоров…",
            .charging: "Зарядка", .notCharging: "Подключено, не заряжается", .cycles: "Циклы",
            .fans: "Вентиляторы", .temperature: "Температура", .power: "Мощность",
            .voltage: "Напряжение", .current: "Ток",
            .lastSpan: "За %@", .minutesShort: "мин", .hourShort: "ч",
            .donate: "Донат криптой",
            .reportIssue: "Сообщить о баге или идее",
            .checkForUpdates: "Проверить обновления", .checkingUpdates: "Проверка обновлений…",
            .upToDate: "Установлена последняя версия", .updateAvailable: "Доступно обновление: %@",
            .downloadUpdate: "Скачать", .autoCheckUpdates: "Проверять обновления автоматически",
            .updateFailed: "Не удалось проверить обновления",
            .removeHint: "Перетащите ячейку сюда, чтобы убрать",
            .diagnostics: "Диагностика", .exportLogs: "Экспорт логов…", .revealLogs: "Показать в Finder",
            .logsHint: "Логи фиксируют ошибки и вылеты. Экспортируйте и приложите к отчёту о баге.",
            .cellsHidden: "Скрыто ячеек: %@ — мало места рядом с чёлкой.",
            .lowPowerMode: "Режим энергосбережения",
        ],
        "fr": [
            .overview: "Aperçu", .history: "Historique", .sensors: "Capteurs",
            .settings: "Réglages", .quit: "Quitter",
            .general: "Général", .menuBar: "Barre menu", .panels: "Panneaux",
            .preview: "Aperçu", .menuBarCells: "Cellules de la barre",
            .cellsHint: "Touchez pour ajouter/retirer · glissez pour réordonner · jusqu’à 5",
            .inMenuBar: "Dans la barre", .available: "Disponibles",
            .dropToAdd: "Déposez ici pour ajouter", .tapToAdd: "Touchez une métrique ci-dessous",
            .defaultSet: "Ensemble par défaut", .useDefault: "Par défaut",
            .show: "Affichage", .cellsShow: "Les cellules affichent",
            .iconValue: "Icône + valeur", .labelValue: "Libellé + valeur", .valueOnly: "Valeur seule",
            .metrics: "Métriques",
            .metricsHint: "Glissez pour réordonner, ou vers Masqué pour ne plus collecter. S’applique à Aperçu et Historique.",
            .active: "Actives", .hiddenNotCollected: "Masquées — non collectées",
            .dropToHide: "Déposez ici pour masquer", .dragToHide: "Glissez une métrique vers Masqué",
            .processLists: "Listes de processus", .showProcessLists: "Afficher les listes de processus",
            .topProcesses: "Top processus par section",
            .cpuSection: "Section CPU", .memorySection: "Section mémoire", .diskSection: "Section disque",
            .updates: "Fréquence d’actualisation", .refreshInterval: "Intervalle d’actualisation",
            .refreshHint: "3× plus lent en mode économie d’énergie et 1,5× sur batterie.",
            .showHistoryTab: "Afficher l’onglet Historique", .keepHistoryFor: "Conserver l’historique",
            .temperatureUnit: "Unité de température", .system: "Système",
            .nerdStats: "Stats avancées", .nerdStatsHint: "Affiche tension, courant et tous les capteurs.",
            .startup: "Démarrage", .launchAtLogin: "Ouvrir à la connexion",
            .keyboardShortcuts: "Raccourcis clavier", .switchTabs: "Changer d’onglet",
            .openSettings: "Ouvrir les réglages", .language: "Langue", .version: "Version",
            .cpu: "CPU", .memory: "Mémoire", .network: "Réseau", .disk: "Disque",
            .gpu: "GPU", .battery: "Batterie",
            .download: "Réception", .upload: "Envoi", .used: "Utilisé", .free: "libre",
            .read: "Lecture", .write: "Écriture", .average: "Moyenne",
            .collectingProcesses: "Collecte des processus…",
            .collectingHistory: "Collecte de l’historique…", .readingSensors: "Lecture des capteurs…",
            .charging: "En charge", .notCharging: "Branché, pas en charge", .cycles: "Cycles",
            .fans: "Ventilateurs", .temperature: "Température", .power: "Puissance",
            .voltage: "Tension", .current: "Courant",
            .lastSpan: "Dernières %@", .minutesShort: "min", .hourShort: "h",
            .donate: "Faire un don en crypto",
            .reportIssue: "Signaler un bug ou une idée",
            .checkForUpdates: "Rechercher des mises à jour", .checkingUpdates: "Recherche de mises à jour…",
            .upToDate: "TinyStats est à jour", .updateAvailable: "Mise à jour disponible : %@",
            .downloadUpdate: "Télécharger", .autoCheckUpdates: "Rechercher les mises à jour automatiquement",
            .updateFailed: "Échec de la recherche de mises à jour",
            .removeHint: "Glissez une cellule ici pour la retirer",
            .diagnostics: "Diagnostic", .exportLogs: "Exporter les journaux…", .revealLogs: "Afficher dans le Finder",
            .logsHint: "Les journaux enregistrent erreurs et plantages. Exportez-les et joignez-les à un rapport de bug.",
            .cellsHidden: "%@ cellule(s) masquée(s) — pas assez de place près de l’encoche.",
            .lowPowerMode: "Mode économie d’énergie",
        ],
        "de": [
            .overview: "Übersicht", .history: "Verlauf", .sensors: "Sensoren",
            .settings: "Einstellungen", .quit: "Beenden",
            .general: "Allgemein", .menuBar: "Menüleiste", .panels: "Bereiche",
            .preview: "Vorschau", .menuBarCells: "Menüleisten-Zellen",
            .cellsHint: "Tippen zum Hinzufügen/Entfernen · ziehen zum Ordnen · bis zu 5",
            .inMenuBar: "In der Menüleiste", .available: "Verfügbar",
            .dropToAdd: "Hier ablegen zum Hinzufügen", .tapToAdd: "Tippe unten auf eine Metrik",
            .defaultSet: "Standardsatz", .useDefault: "Standard",
            .show: "Anzeige", .cellsShow: "Zellen zeigen",
            .iconValue: "Symbol + Wert", .labelValue: "Beschriftung + Wert", .valueOnly: "Nur Wert",
            .metrics: "Metriken",
            .metricsHint: "Ziehen zum Ordnen oder zu Ausgeblendet, um nicht zu erfassen. Gilt für Übersicht und Verlauf.",
            .active: "Aktiv", .hiddenNotCollected: "Ausgeblendet — nicht erfasst",
            .dropToHide: "Hier ablegen zum Ausblenden", .dragToHide: "Metrik zu Ausgeblendet ziehen",
            .processLists: "Prozesslisten", .showProcessLists: "Prozesslisten anzeigen",
            .topProcesses: "Top-Prozesse pro Bereich",
            .cpuSection: "CPU-Bereich", .memorySection: "Speicher-Bereich", .diskSection: "Festplatten-Bereich",
            .updates: "Aktualisierungsrate", .refreshInterval: "Aktualisierungsintervall",
            .refreshHint: "3× langsamer im Energiesparmodus und 1,5× im Akkubetrieb.",
            .showHistoryTab: "Verlauf-Tab anzeigen", .keepHistoryFor: "Verlauf behalten",
            .temperatureUnit: "Temperatureinheit", .system: "System",
            .nerdStats: "Erweiterte Werte", .nerdStatsHint: "Zeigt Spannung, Strom und alle Sensoren.",
            .startup: "Start", .launchAtLogin: "Beim Anmelden öffnen",
            .keyboardShortcuts: "Tastenkürzel", .switchTabs: "Tabs wechseln",
            .openSettings: "Einstellungen öffnen", .language: "Sprache", .version: "Version",
            .cpu: "CPU", .memory: "Speicher", .network: "Netzwerk", .disk: "Festplatte",
            .gpu: "GPU", .battery: "Akku",
            .download: "Download", .upload: "Upload", .used: "Belegt", .free: "frei",
            .read: "Lesen", .write: "Schreiben", .average: "Mittel",
            .collectingProcesses: "Prozessdaten werden erfasst…",
            .collectingHistory: "Verlauf wird erfasst…", .readingSensors: "Sensoren werden gelesen…",
            .charging: "Lädt", .notCharging: "Angeschlossen, lädt nicht", .cycles: "Zyklen",
            .fans: "Lüfter", .temperature: "Temperatur", .power: "Leistung",
            .voltage: "Spannung", .current: "Strom",
            .lastSpan: "Letzte %@", .minutesShort: "Min.", .hourShort: "Std.",
            .donate: "Mit Krypto spenden",
            .reportIssue: "Fehler oder Idee melden",
            .checkForUpdates: "Nach Updates suchen", .checkingUpdates: "Suche nach Updates…",
            .upToDate: "TinyStats ist aktuell", .updateAvailable: "Update verfügbar: %@",
            .downloadUpdate: "Laden", .autoCheckUpdates: "Automatisch nach Updates suchen",
            .updateFailed: "Suche nach Updates fehlgeschlagen",
            .removeHint: "Zelle hierher ziehen, um sie zu entfernen",
            .diagnostics: "Diagnose", .exportLogs: "Protokolle exportieren…", .revealLogs: "Im Finder zeigen",
            .logsHint: "Protokolle erfassen Fehler und Abstürze. Exportieren und dem Fehlerbericht beifügen.",
            .cellsHidden: "%@ Zelle(n) ausgeblendet — zu wenig Platz neben der Notch.",
            .lowPowerMode: "Energiesparmodus",
        ],
        "ko": [
            .overview: "개요", .history: "기록", .sensors: "센서",
            .settings: "설정", .quit: "종료",
            .general: "일반", .menuBar: "메뉴 막대", .panels: "패널",
            .preview: "미리보기", .menuBarCells: "메뉴 막대 셀",
            .cellsHint: "탭하여 추가/제거 · 드래그하여 순서 변경 · 최대 5개",
            .inMenuBar: "메뉴 막대", .available: "사용 가능",
            .dropToAdd: "여기에 놓아 추가", .tapToAdd: "아래 지표를 탭하여 추가",
            .defaultSet: "기본 세트", .useDefault: "기본값",
            .show: "표시", .cellsShow: "셀 표시",
            .iconValue: "아이콘 + 값", .labelValue: "레이블 + 값", .valueOnly: "값만",
            .metrics: "지표",
            .metricsHint: "드래그하여 순서 변경, 또는 숨김으로 이동해 수집 중지. 개요와 기록에 적용됩니다.",
            .active: "활성", .hiddenNotCollected: "숨김 — 수집 안 함",
            .dropToHide: "여기에 놓아 숨기기", .dragToHide: "지표를 숨김으로 드래그",
            .processLists: "프로세스 목록", .showProcessLists: "프로세스 목록 표시",
            .topProcesses: "섹션당 상위 프로세스",
            .cpuSection: "CPU 섹션", .memorySection: "메모리 섹션", .diskSection: "디스크 섹션",
            .updates: "새로고침 빈도", .refreshInterval: "새로고침 간격",
            .refreshHint: "저전력 모드에서 3배, 배터리에서 1.5배 느리게 폴링합니다.",
            .showHistoryTab: "기록 탭 표시", .keepHistoryFor: "기록 보관 기간",
            .temperatureUnit: "온도 단위", .system: "시스템",
            .nerdStats: "고급 정보", .nerdStatsHint: "전압, 전류 및 전체 센서 목록을 표시합니다.",
            .startup: "시작", .launchAtLogin: "로그인 시 실행",
            .keyboardShortcuts: "단축키", .switchTabs: "탭 전환",
            .openSettings: "설정 열기", .language: "언어", .version: "버전",
            .cpu: "CPU", .memory: "메모리", .network: "네트워크", .disk: "디스크",
            .gpu: "GPU", .battery: "배터리",
            .download: "다운로드", .upload: "업로드", .used: "사용됨", .free: "여유",
            .read: "읽기", .write: "쓰기", .average: "평균",
            .collectingProcesses: "프로세스 데이터 수집 중…",
            .collectingHistory: "기록 수집 중…", .readingSensors: "센서 읽는 중…",
            .charging: "충전 중", .notCharging: "연결됨, 충전 안 함", .cycles: "사이클",
            .fans: "팬", .temperature: "온도", .power: "전력",
            .voltage: "전압", .current: "전류",
            .lastSpan: "최근 %@", .minutesShort: "분", .hourShort: "시간",
            .donate: "암호화폐로 후원",
            .reportIssue: "버그 또는 제안 보내기",
            .checkForUpdates: "업데이트 확인", .checkingUpdates: "업데이트 확인 중…",
            .upToDate: "최신 버전입니다", .updateAvailable: "업데이트 있음: %@",
            .downloadUpdate: "다운로드", .autoCheckUpdates: "자동으로 업데이트 확인",
            .updateFailed: "업데이트를 확인할 수 없습니다",
            .removeHint: "셀을 여기로 끌어 제거",
            .diagnostics: "진단", .exportLogs: "로그 내보내기…", .revealLogs: "Finder에서 보기",
            .logsHint: "로그는 오류와 충돌을 기록합니다. 내보내 버그 신고에 첨부하세요.",
            .cellsHidden: "%@개 셀 숨김 — 노치 옆 공간이 부족합니다.",
            .lowPowerMode: "저전력 모드",
        ],
        "ja": [
            .overview: "概要", .history: "履歴", .sensors: "センサー",
            .settings: "設定", .quit: "終了",
            .general: "一般", .menuBar: "メニューバー", .panels: "パネル",
            .preview: "プレビュー", .menuBarCells: "メニューバーセル",
            .cellsHint: "タップで追加/削除・ドラッグで並べ替え・最大5個",
            .inMenuBar: "メニューバー内", .available: "利用可能",
            .dropToAdd: "ここにドロップして追加", .tapToAdd: "下の項目をタップして追加",
            .defaultSet: "デフォルトセット", .useDefault: "デフォルト",
            .show: "表示", .cellsShow: "セルの表示",
            .iconValue: "アイコン + 値", .labelValue: "ラベル + 値", .valueOnly: "値のみ",
            .metrics: "メトリクス",
            .metricsHint: "ドラッグで並べ替え、または「非表示」に移動して収集を停止。概要と履歴に適用されます。",
            .active: "アクティブ", .hiddenNotCollected: "非表示 — 収集なし",
            .dropToHide: "ここにドロップして非表示", .dragToHide: "項目を「非表示」へドラッグ",
            .processLists: "プロセス一覧", .showProcessLists: "プロセス一覧を表示",
            .topProcesses: "セクションごとの上位プロセス",
            .cpuSection: "CPU セクション", .memorySection: "メモリ セクション", .diskSection: "ディスク セクション",
            .updates: "更新頻度", .refreshInterval: "更新間隔",
            .refreshHint: "低電力モードで3倍、バッテリーで1.5倍ゆっくり取得します。",
            .showHistoryTab: "履歴タブを表示", .keepHistoryFor: "履歴の保持期間",
            .temperatureUnit: "温度の単位", .system: "システム",
            .nerdStats: "詳細データ", .nerdStatsHint: "電圧・電流と全センサー一覧を表示します。",
            .startup: "起動", .launchAtLogin: "ログイン時に起動",
            .keyboardShortcuts: "キーボードショートカット", .switchTabs: "タブ切り替え",
            .openSettings: "設定を開く", .language: "言語", .version: "バージョン",
            .cpu: "CPU", .memory: "メモリ", .network: "ネットワーク", .disk: "ディスク",
            .gpu: "GPU", .battery: "バッテリー",
            .download: "ダウンロード", .upload: "アップロード", .used: "使用中", .free: "空き",
            .read: "読み込み", .write: "書き込み", .average: "平均",
            .collectingProcesses: "プロセスデータを収集中…",
            .collectingHistory: "履歴を収集中…", .readingSensors: "センサーを読み取り中…",
            .charging: "充電中", .notCharging: "接続中、充電していません", .cycles: "サイクル",
            .fans: "ファン", .temperature: "温度", .power: "電力",
            .voltage: "電圧", .current: "電流",
            .lastSpan: "直近 %@", .minutesShort: "分", .hourShort: "時間",
            .donate: "暗号資産で寄付",
            .reportIssue: "バグ・要望を報告",
            .checkForUpdates: "アップデートを確認", .checkingUpdates: "アップデートを確認中…",
            .upToDate: "TinyStats は最新です", .updateAvailable: "アップデートあり: %@",
            .downloadUpdate: "ダウンロード", .autoCheckUpdates: "アップデートを自動確認",
            .updateFailed: "アップデートを確認できませんでした",
            .removeHint: "セルをここにドラッグして削除",
            .diagnostics: "診断", .exportLogs: "ログを書き出す…", .revealLogs: "Finderで表示",
            .logsHint: "ログはエラーとクラッシュを記録します。書き出してバグ報告に添付してください。",
            .cellsHidden: "%@個のセルを非表示 — ノッチ横の余白が足りません。",
            .lowPowerMode: "低電力モード",
        ],
        "zh": [
            .overview: "概览", .history: "历史", .sensors: "传感器",
            .settings: "设置", .quit: "退出",
            .general: "通用", .menuBar: "菜单栏", .panels: "面板",
            .preview: "预览", .menuBarCells: "菜单栏单元",
            .cellsHint: "点按添加/移除 · 拖动排序 · 最多 5 个",
            .inMenuBar: "菜单栏中", .available: "可用",
            .dropToAdd: "拖到此处添加", .tapToAdd: "点按下方指标以添加",
            .defaultSet: "默认组合", .useDefault: "默认",
            .show: "显示", .cellsShow: "单元显示",
            .iconValue: "图标 + 数值", .labelValue: "标签 + 数值", .valueOnly: "仅数值",
            .metrics: "指标",
            .metricsHint: "拖动排序，或移到“隐藏”以停止采集。应用于概览和历史。",
            .active: "活动", .hiddenNotCollected: "隐藏 — 不采集",
            .dropToHide: "拖到此处隐藏", .dragToHide: "将指标拖到“隐藏”",
            .processLists: "进程列表", .showProcessLists: "显示进程列表",
            .topProcesses: "每节顶部进程",
            .cpuSection: "CPU 部分", .memorySection: "内存部分", .diskSection: "磁盘部分",
            .updates: "刷新频率", .refreshInterval: "刷新间隔",
            .refreshHint: "低电量模式下慢 3 倍，电池供电时慢 1.5 倍。",
            .showHistoryTab: "显示历史标签", .keepHistoryFor: "历史保留时长",
            .temperatureUnit: "温度单位", .system: "系统",
            .nerdStats: "高级数据", .nerdStatsHint: "显示电压、电流和完整传感器列表。",
            .startup: "启动", .launchAtLogin: "登录时启动",
            .keyboardShortcuts: "键盘快捷键", .switchTabs: "切换标签",
            .openSettings: "打开设置", .language: "语言", .version: "版本",
            .cpu: "CPU", .memory: "内存", .network: "网络", .disk: "磁盘",
            .gpu: "GPU", .battery: "电池",
            .download: "下载", .upload: "上传", .used: "已用", .free: "可用",
            .read: "读取", .write: "写入", .average: "平均",
            .collectingProcesses: "正在采集进程数据…",
            .collectingHistory: "正在采集历史…", .readingSensors: "正在读取传感器…",
            .charging: "充电中", .notCharging: "已接通，未充电", .cycles: "循环次数",
            .fans: "风扇", .temperature: "温度", .power: "功率",
            .voltage: "电压", .current: "电流",
            .lastSpan: "最近 %@", .minutesShort: "分钟", .hourShort: "小时",
            .donate: "用加密货币捐赠",
            .reportIssue: "反馈问题或建议",
            .checkForUpdates: "检查更新", .checkingUpdates: "正在检查更新…",
            .upToDate: "TinyStats 已是最新", .updateAvailable: "有可用更新：%@",
            .downloadUpdate: "下载", .autoCheckUpdates: "自动检查更新",
            .updateFailed: "无法检查更新",
            .removeHint: "将单元拖到此处以移除",
            .diagnostics: "诊断", .exportLogs: "导出日志…", .revealLogs: "在访达中显示",
            .logsHint: "日志记录错误和崩溃。导出并附加到错误报告中。",
            .cellsHidden: "已隐藏 %@ 个单元 — 刘海旁空间不足。",
            .lowPowerMode: "低电量模式",
        ],
    ]
}
