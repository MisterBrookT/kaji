import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case en
    case zh
    case ptBR = "pt-BR"
    case es

    public var label: String {
        switch self {
        case .en: "EN"
        case .zh: "中文"
        case .ptBR: "PT-BR"
        case .es: "ES"
        }
    }
}

public typealias Lang = AppLanguage

public enum LanguagePrefsLogic {
    public struct Resolution: Equatable, Sendable {
        public let language: AppLanguage
        public let shouldPersist: Bool
    }

    public static func resolve(
        storedRawValue: String?,
        hadExistingPreferences: Bool,
        preferredLanguages: [String]
    ) -> Resolution {
        if let storedRawValue, let stored = AppLanguage(rawValue: storedRawValue) {
            return Resolution(language: stored, shouldPersist: false)
        }
        if storedRawValue != nil {
            return Resolution(language: .en, shouldPersist: true)
        }
        if hadExistingPreferences {
            let preferred = preferredLanguages.first ?? "en"
            return Resolution(
                language: preferred.hasPrefix("zh") ? .zh : .en,
                shouldPersist: true
            )
        }
        return Resolution(language: .en, shouldPersist: true)
    }
}

public enum L10n {
    public enum K: CaseIterable, Sendable {
        case fiveHQuota, week, quit, stale, waiting, needPython
        case refreshNow, quitApp, settings, advancedSettings, appearance, language, providers, show
        case hide, on, off
        case usage, showUsed, showRemaining
        case updateTo, checkUpdates, updateChecking, updateCurrent, updateFailed
        case system, keepAwake, keepAwakeOn, keepAwakeOff, keepAwakeTurningOn, keepAwakeTurningOff, keepAwakeFailed
        case work, focusLength, breakLength, skipBreak, breakOverlay
        case fixedPlan
        case launchAtLogin
        case modules, modulesHint
        case moduleQuota, moduleWork, moduleSystem, moduleGoals, moduleAINews
        case aiNews, dataSource, updated, loading, noHotNews, retry, sources, refreshInterval
    }

    private struct Text {
        let en: String
        let zh: String
        let ptBR: String
        let es: String

        subscript(language: AppLanguage) -> String {
            switch language {
            case .en: en
            case .zh: zh
            case .ptBR: ptBR
            case .es: es
            }
        }
    }

    private static let table: [K: Text] = [
        .fiveHQuota: .init(en: "5h quota", zh: "5小时额度", ptBR: "Cota de 5h", es: "Cuota de 5h"),
        .week: .init(en: "7d", zh: "7天", ptBR: "7d", es: "7d"),
        .quit: .init(en: "Quit", zh: "退出", ptBR: "Sair", es: "Salir"),
        .stale: .init(en: "stale", zh: "已过期", ptBR: "desatualizado", es: "desactualizado"),
        .waiting: .init(en: "waiting for quota…", zh: "等待额度…", ptBR: "aguardando cota…", es: "esperando cuota…"),
        .needPython: .init(
            en: "Needs Python 3 · run  xcode-select --install",
            zh: "需要 Python 3 · 运行  xcode-select --install",
            ptBR: "Requer Python 3 · execute  xcode-select --install",
            es: "Requiere Python 3 · ejecuta  xcode-select --install"
        ),
        .refreshNow: .init(en: "Refresh Now", zh: "立即刷新", ptBR: "Atualizar agora", es: "Actualizar ahora"),
        .quitApp: .init(en: "Quit Kaji", zh: "退出 Kaji", ptBR: "Sair do Kaji", es: "Salir de Kaji"),
        .settings: .init(en: "Settings", zh: "设置", ptBR: "Ajustes", es: "Ajustes"),
        .advancedSettings: .init(en: "Advanced", zh: "高级设置", ptBR: "Avançado", es: "Avanzado"),
        .appearance: .init(en: "Appearance", zh: "外观", ptBR: "Aparência", es: "Apariencia"),
        .language: .init(en: "Language", zh: "语言", ptBR: "Idioma", es: "Idioma"),
        .providers: .init(en: "Providers", zh: "提供商", ptBR: "Provedores", es: "Proveedores"),
        .show: .init(en: "Show", zh: "显示", ptBR: "Mostrar", es: "Mostrar"),
        .hide: .init(en: "Hide", zh: "隐藏", ptBR: "Ocultar", es: "Ocultar"),
        .on: .init(en: "On", zh: "开", ptBR: "Sim", es: "Sí"),
        .off: .init(en: "Off", zh: "关", ptBR: "Não", es: "No"),
        .usage: .init(en: "Usage", zh: "用量", ptBR: "Uso", es: "Uso"),
        .showUsed: .init(en: "Used", zh: "已用", ptBR: "Usado", es: "Usado"),
        .showRemaining: .init(en: "Remaining", zh: "剩余", ptBR: "Restante", es: "Restante"),
        .updateTo: .init(en: "Update to", zh: "更新到", ptBR: "Atualizar para", es: "Actualizar a"),
        .checkUpdates: .init(en: "Check for Updates…", zh: "检查更新…", ptBR: "Buscar atualizações…", es: "Buscar actualizaciones…"),
        .updateChecking: .init(en: "Checking…", zh: "检查中…", ptBR: "Verificando…", es: "Comprobando…"),
        .updateCurrent: .init(en: "Up to date", zh: "已是最新", ptBR: "Atualizado", es: "Actualizado"),
        .updateFailed: .init(en: "Update check failed", zh: "检查更新失败", ptBR: "Falha ao buscar atualização", es: "Error al buscar actualizaciones"),
        .system: .init(en: "System", zh: "系统", ptBR: "Sistema", es: "Sistema"),
        .keepAwake: .init(en: "Prevent Sleep", zh: "禁止休眠", ptBR: "Impedir repouso", es: "Impedir reposo"),
        .keepAwakeOn: .init(en: "Awake On", zh: "不休眠已开", ptBR: "Repouso bloqueado", es: "Reposo bloqueado"),
        .keepAwakeOff: .init(en: "Awake Off", zh: "不休眠关", ptBR: "Repouso liberado", es: "Reposo permitido"),
        .keepAwakeTurningOn: .init(en: "Turning On…", zh: "开启中…", ptBR: "Ativando…", es: "Activando…"),
        .keepAwakeTurningOff: .init(en: "Turning Off…", zh: "关闭中…", ptBR: "Desativando…", es: "Desactivando…"),
        .keepAwakeFailed: .init(en: "Awake Failed", zh: "设置失败", ptBR: "Falha ao configurar", es: "Error de configuración"),
        .work: .init(en: "Work", zh: "工作", ptBR: "Trabalho", es: "Trabajo"),
        .fixedPlan: .init(en: "Schedule", zh: "日程", ptBR: "Agenda", es: "Horario"),
        .focusLength: .init(en: "Focus", zh: "专注", ptBR: "Foco", es: "Enfoque"),
        .breakLength: .init(en: "Break", zh: "休息", ptBR: "Pausa", es: "Descanso"),
        .skipBreak: .init(en: "Allow Skip", zh: "允许跳过", ptBR: "Permitir pular", es: "Permitir omitir"),
        .breakOverlay: .init(en: "Hard Break", zh: "强制休息", ptBR: "Pausa forçada", es: "Descanso forzado"),
        .launchAtLogin: .init(en: "Launch", zh: "开机启动", ptBR: "Iniciar", es: "Iniciar"),
        .modules: .init(en: "Modules", zh: "模块", ptBR: "Módulos", es: "Módulos"),
        .modulesHint: .init(
            en: "Default is Quota only. Turn on what you need.",
            zh: "默认只开 Quota。按需打开其余。",
            ptBR: "Por padrão, só Quota. Ative o que precisar.",
            es: "Por defecto, solo Quota. Activa lo que necesites."
        ),
        .moduleQuota: .init(en: "Quota", zh: "Quota", ptBR: "Quota", es: "Quota"),
        .moduleWork: .init(en: "Work / Break", zh: "Work / Break", ptBR: "Trabalho / Pausa", es: "Trabajo / Descanso"),
        .moduleSystem: .init(en: "System", zh: "System", ptBR: "Sistema", es: "Sistema"),
        .moduleGoals: .init(en: "Goals", zh: "Goals", ptBR: "Metas", es: "Metas"),
        .moduleAINews: .init(en: "AI News", zh: "AI 新闻", ptBR: "Notícias de IA", es: "Noticias de IA"),
        .aiNews: .init(en: "AI News", zh: "AI 新闻", ptBR: "Notícias de IA", es: "Noticias de IA"),
        .dataSource: .init(en: "Data source", zh: "数据来源", ptBR: "Fonte de dados", es: "Fuente de datos"),
        .updated: .init(en: "Updated", zh: "更新于", ptBR: "Atualizado", es: "Actualizado"),
        .loading: .init(en: "Loading…", zh: "加载中…", ptBR: "Carregando…", es: "Cargando…"),
        .noHotNews: .init(en: "No hot news", zh: "暂无热点", ptBR: "Sem notícias em alta", es: "Sin noticias destacadas"),
        .retry: .init(en: "Retry", zh: "重试", ptBR: "Tentar novamente", es: "Reintentar"),
        .sources: .init(en: "sources", zh: "个来源", ptBR: "fontes", es: "fuentes"),
        .refreshInterval: .init(en: "Refresh", zh: "刷新间隔", ptBR: "Atualização", es: "Actualización")
    ]

    public static func t(_ key: K, _ language: AppLanguage) -> String {
        table[key]?[language] ?? ""
    }
}
