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
        case cliIntegrationHint, cliExamplePrompt, copyPrompt
        case moduleQuota, moduleWork, moduleSystem, moduleGoals, moduleAINews
        case aiNews, dataSource, updated, loading, noHotNews, retry, sources, refreshInterval
        case goalGroup, goalGroupingNone, goalGroupingByTag, goalGroupingByCreatedTime
        case goalGroupUntagged, goalGroupToday, goalGroupYesterday, goalGroupThisWeek, goalGroupEarlier
        case permissions, gmailCredential, gmailCredentialWhy, loginPermission, loginPermissionWhy
        case sleepPermission, sleepPermissionWhy, authorized, notAuthorized, needsReauthorization, authorize
        case sleepApprovalTitle, sleepApprovalMessage, openSystemSettings, cancel
        case sleepRepairTitle, sleepRepairMessage, repairHelper
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
        .cliIntegrationHint: .init(
            en: "Agents manage Kaji goals through the kaji command built with this app.",
            zh: "Agent 通过随本应用构建的 kaji 命令管理 Kaji goals。",
            ptBR: "Agentes gerenciam as metas do Kaji pelo comando kaji criado com este app.",
            es: "Los agentes gestionan las metas de Kaji mediante el comando kaji incluido con esta app."
        ),
        .cliExamplePrompt: .init(
            en: "Read `kaji --help`, then create a skill called kaji",
            zh: "读 `kaji --help`,创建一个叫 kaji 的 skill",
            ptBR: "Leia `kaji --help` e crie uma skill chamada kaji",
            es: "Lee `kaji --help` y crea una skill llamada kaji"
        ),
        .copyPrompt: .init(en: "Copy prompt", zh: "复制提示词", ptBR: "Copiar prompt", es: "Copiar prompt"),
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
        .refreshInterval: .init(en: "Refresh", zh: "刷新间隔", ptBR: "Atualização", es: "Actualización"),
        .goalGroup: .init(en: "Group", zh: "分组", ptBR: "Agrupar", es: "Agrupar"),
        .goalGroupingNone: .init(en: "No Grouping", zh: "不分组", ptBR: "Sem agrupamento", es: "Sin agrupar"),
        .goalGroupingByTag: .init(en: "By Tag", zh: "按标签", ptBR: "Por etiqueta", es: "Por etiqueta"),
        .goalGroupingByCreatedTime: .init(en: "By Created Time", zh: "按创建时间", ptBR: "Por data de criação", es: "Por fecha de creación"),
        .goalGroupUntagged: .init(en: "Untagged", zh: "无标签", ptBR: "Sem etiqueta", es: "Sin etiqueta"),
        .goalGroupToday: .init(en: "Today", zh: "今天", ptBR: "Hoje", es: "Hoy"),
        .goalGroupYesterday: .init(en: "Yesterday", zh: "昨天", ptBR: "Ontem", es: "Ayer"),
        .goalGroupThisWeek: .init(en: "This Week", zh: "本周", ptBR: "Esta semana", es: "Esta semana"),
        .goalGroupEarlier: .init(en: "Earlier", zh: "更早", ptBR: "Anteriores", es: "Anteriores"),
        .permissions: .init(en: "Permissions", zh: "授权", ptBR: "Autorizações", es: "Permisos"),
        .gmailCredential: .init(en: "Gmail credential", zh: "Gmail 凭据", ptBR: "Credencial do Gmail", es: "Credencial de Gmail"),
        .gmailCredentialWhy: .init(en: "Reads Gmail securely for Mail Brief.", zh: "安全读取 Gmail 以生成邮件简报。", ptBR: "Lê o Gmail com segurança para o resumo.", es: "Lee Gmail de forma segura para el resumen."),
        .loginPermission: .init(en: "Launch at login", zh: "登录时启动", ptBR: "Iniciar ao entrar", es: "Iniciar al entrar"),
        .loginPermissionWhy: .init(en: "Keeps Kaji available after you sign in.", zh: "登录 Mac 后自动保持 Kaji 可用。", ptBR: "Mantém o Kaji disponível após entrar.", es: "Mantiene Kaji disponible tras iniciar sesión."),
        .sleepPermission: .init(en: "Prevent sleep helper", zh: "防休眠助手", ptBR: "Auxiliar antirrepouso", es: "Asistente antirreposo"),
        .sleepPermissionWhy: .init(en: "Keeps the Mac awake during active work.", zh: "工作期间让 Mac 保持唤醒。", ptBR: "Mantém o Mac ativo durante o trabalho.", es: "Mantiene el Mac activo durante el trabajo."),
        .authorized: .init(en: "Authorized", zh: "已授权", ptBR: "Autorizado", es: "Autorizado"),
        .notAuthorized: .init(en: "Not authorized", zh: "未授权", ptBR: "Não autorizado", es: "No autorizado"),
        .needsReauthorization: .init(en: "Needs re-authorization", zh: "需要重新授权", ptBR: "Requer nova autorização", es: "Requiere nueva autorización"),
        .authorize: .init(en: "Authorize", zh: "授权", ptBR: "Autorizar", es: "Autorizar"),
        .sleepApprovalTitle: .init(en: "Allow Prevent Sleep", zh: "允许 Kaji 防止休眠", ptBR: "Permitir impedir repouso", es: "Permitir impedir reposo"),
        .sleepApprovalMessage: .init(
            en: "macOS requires one approval. In Login Items & Extensions, turn on Kaji under App Background Activity, then return here. Later switches will not ask again.",
            zh: "macOS 需要一次授权。请在“登录项与扩展”的“App 后台活动”中开启 Kaji，然后返回这里；之后切换不再重复询问。",
            ptBR: "O macOS exige uma aprovação. Em Itens de Início e Extensões, ative o Kaji em Atividade em Segundo Plano e volte aqui. As próximas mudanças não pedirão novamente.",
            es: "macOS requiere una autorización. En Ítems de inicio y extensiones, activa Kaji en Actividad en segundo plano y vuelve aquí. Los cambios posteriores no volverán a solicitarla."
        ),
        .openSystemSettings: .init(en: "Open System Settings", zh: "打开系统设置", ptBR: "Abrir Ajustes do Sistema", es: "Abrir Ajustes del Sistema"),
        .cancel: .init(en: "Cancel", zh: "取消", ptBR: "Cancelar", es: "Cancelar"),
        .sleepRepairTitle: .init(en: "Repair Prevent Sleep", zh: "修复防休眠助手", ptBR: "Reparar auxiliar antirrepouso", es: "Reparar asistente antirreposo"),
        .sleepRepairMessage: .init(
            en: "The helper from an earlier Kaji build can no longer start. Kaji can replace it now; macOS may then request one approval.",
            zh: "旧版 Kaji 注册的防休眠助手已经无法启动。Kaji 可以立即替换它；随后 macOS 可能要求一次授权。",
            ptBR: "O auxiliar de uma versão anterior do Kaji não inicia mais. O Kaji pode substituí-lo agora; depois, o macOS pode pedir uma autorização.",
            es: "El asistente de una versión anterior de Kaji ya no puede iniciarse. Kaji puede reemplazarlo ahora; después, macOS puede pedir una autorización."
        ),
        .repairHelper: .init(en: "Repair Helper", zh: "修复助手", ptBR: "Reparar auxiliar", es: "Reparar asistente"),
    ]

    public static func t(_ key: K, _ language: AppLanguage) -> String {
        table[key]?[language] ?? ""
    }
}
