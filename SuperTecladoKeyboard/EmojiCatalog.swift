import Foundation

#if SUPER_TECLADO_LOGIC_TESTS
@testable import SuperTeclado
#endif

struct EmojiCategory: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let emojis: [String]
}

enum EmojiCatalog {
    static let categories: [EmojiCategory] = [
        EmojiCategory(
            id: "smileys",
            title: "Emoticonos y emociones",
            symbol: "face.smiling",
            emojis: split("😀😃😄😁😆😅🤣😂🙂🙃🫠😉😊😇🥰😍🤩😘😗☺️😚😙🥲😋😛😜🤪😝🤑🤗🤭🫢🫣🤫🤔🫡🤐🤨😐😑😶🫥😏😒🙄😬🤥😌😔😪🤤😴😷🤒🤕🤢🤮🤧🥵🥶🥴😵🤯🤠🥳🥸😎🤓🧐😕🫤😟🙁☹️😮😯😲😳🥺🥹😦😧😨😰😥😢😭😱😖😣😞😓😩😫🥱😤😡😠🤬😈👿💀☠️💩🤡👹👺👻👽👾🤖😺😸😹😻😼😽🙀😿😾🙈🙉🙊💋💌💘💝💖💗💓💞💕💟❣️💔❤️🧡💛💚💙💜🤎🖤🤍💯💢💥💫💦💨💬💭💤")
        ),
        EmojiCategory(
            id: "people",
            title: "Personas y gestos",
            symbol: "hand.wave",
            emojis: split("👋🤚🖐️✋🖖🫱🫲🫳🫴👌🤌🤏✌️🤞🫰🤟🤘🤙👈👉👆🖕👇☝️🫵👍👎✊👊🤛🤜👏🙌🫶👐🤲🤝🙏✍️💅🤳💪🦾🦿🦵🦶👂🦻👃🧠🫀🫁🦷🦴👀👁️👅👄🫦👶🧒👦👧🧑👱👨🧔👩🧓👴👵🙍🙎🙅🙆💁🙋🧏🙇🤦🤷👮🕵️💂🥷👷🫅🤴👸👳👲🧕🤵👰🤰🫄🤱👼🎅🤶🦸🦹🧙🧚🧛🧜🧝🧞🧟🧌💆💇🚶🧍🧎🏃💃🕺🕴️👯🧖🧗🤺🏇⛷️🏂🏌️🏄🚣🏊⛹️🏋️🚴🚵🤸🤼🤽🤾🤹🧘🛀🛌👭👫👬💏💑👪🗣️👤👥🫂👣")
        ),
        EmojiCategory(
            id: "nature",
            title: "Animales y naturaleza",
            symbol: "pawprint",
            emojis: split("🐶🐱🐭🐹🐰🦊🐻🐼🐻‍❄️🐨🐯🦁🐮🐷🐽🐸🐵🐒🐔🐧🐦🐤🐣🐥🦆🦅🦉🦇🐺🐗🐴🦄🐝🪱🐛🦋🐌🐞🐜🪰🪲🪳🦟🦗🕷️🕸️🦂🐢🐍🦎🦖🦕🐙🦑🦐🦞🦀🪼🐡🐠🐟🐬🐳🐋🦈🦭🐊🐅🐆🦓🦍🦧🦣🐘🦛🦏🐪🐫🦒🦘🦬🐃🐂🐄🐎🐖🐏🐑🦙🐐🦌🐕🐩🦮🐈🐈‍⬛🪶🐓🦃🦤🦚🦜🦢🦩🕊️🐇🦝🦨🦡🦫🦦🦥🐁🐀🐿️🦔🐾🐉🐲🌵🎄🌲🌳🌴🪵🌱🌿☘️🍀🎍🪴🎋🍃🍂🍁🍄🐚🪨🌾💐🌷🌹🥀🌺🌸🌼🌻🌞🌝🌛🌜🌚🌕🌖🌗🌘🌑🌒🌓🌔🌙🌎🌍🌏🪐⭐🌟✨⚡☄️🔥🌪️🌈☀️🌤️⛅🌥️☁️🌦️🌧️⛈️🌩️🌨️❄️☃️⛄🌬️💧🫧☔☂️🌊🌫️")
        ),
        EmojiCategory(
            id: "food",
            title: "Comida y bebida",
            symbol: "fork.knife",
            emojis: split("🍏🍎🍐🍊🍋🍌🍉🍇🍓🫐🍈🍒🍑🥭🍍🥥🥝🍅🍆🥑🥦🥬🥒🌶️🫑🌽🥕🫒🧄🧅🥔🍠🫘🥐🥯🍞🥖🥨🧀🥚🍳🧈🥞🧇🥓🥩🍗🍖🌭🍔🍟🍕🫓🥪🥙🧆🌮🌯🫔🥗🥘🫕🥫🍝🍜🍲🍛🍣🍱🥟🦪🍤🍙🍚🍘🍥🥠🥮🍢🍡🍧🍨🍦🥧🧁🍰🎂🍮🍭🍬🍫🍿🍩🍪🌰🥜🍯🥛🍼🫖☕🍵🧃🥤🧋🍶🍺🍻🥂🍷🥃🍸🍹🧉🍾🧊🥄🍴🍽️🥣🥡🥢🧂")
        ),
        EmojiCategory(
            id: "activities",
            title: "Actividades",
            symbol: "soccerball",
            emojis: split("⚽🏀🏈⚾🥎🎾🏐🏉🥏🎱🪀🏓🏸🏒🏑🥍🏏🪃🥅⛳🪁🏹🎣🤿🥊🥋🎽🛹🛼🛷⛸️🥌🎿🪂🏆🥇🥈🥉🏅🎖️🏵️🎗️🎫🎟️🎪🎭🩰🎨🎬🎤🎧🎼🎹🥁🪘🎷🎺🪗🎸🪕🎻🎲♟️🎯🎳🎮🎰🧩")
        ),
        EmojiCategory(
            id: "travel",
            title: "Viajes y lugares",
            symbol: "car",
            emojis: split("🚗🚕🚙🚌🚎🏎️🚓🚑🚒🚐🛻🚚🚛🚜🦯🦽🦼🛴🚲🛵🏍️🛺🚨🚔🚍🚘🚖🚡🚠🚟🚃🚋🚞🚝🚄🚅🚈🚂🚆🚇🚊🚉✈️🛫🛬🛩️💺🛰️🚀🛸🚁🛶⛵🚤🛥️🛳️⛴️🚢⚓🪝⛽🚧🚦🚥🚏🗺️🗿🗽🗼🏰🏯🏟️🎡🎢🎠⛲⛱️🏖️🏝️🏜️🌋⛰️🏔️🗻🏕️⛺🛖🏠🏡🏘️🏚️🏗️🏭🏢🏬🏣🏤🏥🏦🏨🏪🏫🏩💒🏛️⛪🕌🕍🛕🕋⛩️🛤️🛣️🗾🎑🏞️🌅🌄🌠🎇🎆🌇🌆🏙️🌃🌌🌉🌁")
        ),
        EmojiCategory(
            id: "objects",
            title: "Objetos",
            symbol: "lightbulb",
            emojis: split("⌚📱📲💻⌨️🖥️🖨️🖱️🖲️🕹️🗜️💽💾💿📀📼📷📸📹🎥📽️🎞️📞☎️📟📠📺📻🎙️🎚️🎛️🧭⏱️⏲️⏰🕰️⌛⏳📡🔋🪫🔌💡🔦🕯️🪔🧯🛢️💸💵💴💶💷🪙💰💳💎⚖️🪜🧰🪛🔧🔨⚒️🛠️⛏️🪚🔩⚙️🪤🧱⛓️🧲🔫💣🧨🪓🔪🗡️⚔️🛡️🚬⚰️🪦⚱️🏺🔮📿🧿🪬💈⚗️🔭🔬🕳️🩹🩺💊💉🩸🧬🦠🧫🧪🌡️🧹🪠🧺🧻🚽🚰🚿🛁🧼🪥🪒🧽🪣🧴🛎️🔑🗝️🚪🪑🛋️🛏️🧸🪆🖼️🪞🪟🛍️🛒🎁🎈🎏🎀🪄🪅🎊🎉🎎🏮🎐🧧✉️📩📨📧📥📤📦🏷️🪧📪📫📬📭📮📯📜📃📄📑🧾📊📈📉🗒️🗓️📆📅🗑️📇🗃️🗳️🗄️📋📁📂🗂️🗞️📰📓📔📒📕📗📘📙📚📖🔖🧷🔗📎🖇️📐📏🧮📌📍✂️🖊️🖋️✒️🖌️🖍️📝✏️🔍🔎🔏🔐🔒🔓")
        ),
        EmojiCategory(
            id: "symbols",
            title: "Símbolos",
            symbol: "heart",
            emojis: split("☮️✝️☪️🕉️☸️✡️🔯🕎☯️☦️🛐⛎♈♉♊♋♌♍♎♏♐♑♒♓🆔⚛️☢️☣️📴📳🆚💮㊙️㊗️🅰️🅱️🆎🆑🅾️🆘❌⭕🛑⛔📛🚫♨️🚷🚯🚳🚱🔞📵🚭❗❕❓❔‼️⁉️🔅🔆〽️⚠️🚸🔱⚜️🔰♻️✅💹❇️✳️❎🌐💠Ⓜ️🌀🏧🚾♿🅿️🛗🛂🛃🛄🛅🚹🚺🚼⚧️🚻🚮🎦📶🔣ℹ️🔤🔡🔠🆖🆗🆙🆒🆕🆓0️⃣1️⃣2️⃣3️⃣4️⃣5️⃣6️⃣7️⃣8️⃣9️⃣🔟🔢#️⃣*️⃣⏏️▶️⏸️⏯️⏹️⏺️⏭️⏮️⏩⏪⏫⏬◀️🔼🔽➡️⬅️⬆️⬇️↗️↘️↙️↖️↕️↔️↪️↩️⤴️⤵️🔀🔁🔂🔄🔃🎵🎶➕➖➗✖️🟰♾️💲💱™️©️®️🔚🔙🔛🔝🔜〰️➰➿✔️☑️🔘🔴🟠🟡🟢🔵🟣⚫⚪🟤🔺🔻🔸🔹🔶🔷🔳🔲▪️▫️◾◽◼️◻️🟥🟧🟨🟩🟦🟪⬛⬜🟫🔈🔇🔉🔊🔔🔕📣📢🗯️♠️♣️♥️♦️🃏🎴🀄🕐🕑🕒🕓🕔🕕🕖🕗🕘🕙🕚🕛")
        ),
        EmojiCategory(
            id: "flags",
            title: "Banderas",
            symbol: "flag",
            emojis: split("🏁🚩🎌🏴🏳️🏳️‍🌈🏳️‍⚧️🏴‍☠️🇪🇸🇲🇽🇦🇷🇨🇴🇨🇱🇵🇪🇻🇪🇪🇨🇬🇹🇨🇺🇧🇴🇩🇴🇭🇳🇵🇾🇸🇻🇳🇮🇨🇷🇵🇦🇺🇾🇵🇷🇬🇶🇺🇸🇨🇦🇧🇷🇵🇹🇫🇷🇩🇪🇮🇹🇬🇧🇮🇪🇳🇱🇧🇪🇨🇭🇦🇹🇸🇪🇳🇴🇩🇰🇫🇮🇵🇱🇬🇷🇹🇷🇺🇦🇨🇳🇯🇵🇰🇷🇮🇳🇦🇺🇳🇿🇿🇦🇲🇦🇪🇬🇳🇬🇸🇦🇦🇪🇮🇱🇪🇺🇺🇳")
        )
    ]

    private static func split(_ value: String) -> [String] {
        var seen = Set<String>()
        return value.map(String.init).filter { seen.insert($0).inserted }
    }
}

/// Emojis que se sugieren en la barra al escribir ciertas palabras, como en Gboard.
enum EmojiKeywords {
    static func emoji(for word: String) -> String? {
        map[WordDictionary.fold(word.lowercased())]
    }

    private static let map: [String: String] = [
        "jaja": "😂", "jajaja": "😂", "jajajaja": "😂", "lol": "😂", "risa": "😂", "jeje": "😄", "xd": "😆",
        "feliz": "😊", "contento": "😊", "contenta": "😊", "alegria": "😁", "sonrisa": "😊",
        "triste": "😢", "pena": "😔", "llorar": "😭", "lloro": "😭",
        "amor": "❤️", "corazon": "❤️", "quiero": "❤️", "amo": "😍", "guapo": "😍", "guapa": "😍", "bonito": "😍", "bonita": "😍",
        "beso": "😘", "besos": "😘", "besito": "😘", "abrazo": "🤗", "abrazos": "🤗",
        "gracias": "🙏", "porfa": "🙏", "favor": "🙏",
        "hola": "👋", "adios": "👋", "chao": "👋", "chau": "👋",
        "ok": "👌", "vale": "👌", "perfecto": "👌", "bien": "👍", "genial": "🙌", "guay": "😎", "cool": "😎",
        "fiesta": "🎉", "felicidades": "🎉", "enhorabuena": "👏", "aplausos": "👏", "bravo": "👏",
        "cumpleanos": "🎂", "tarta": "🎂", "pastel": "🍰", "regalo": "🎁", "regalos": "🎁",
        "fuego": "🔥", "dinero": "💰", "pasta": "🍝", "pizza": "🍕", "hamburguesa": "🍔", "cafe": "☕",
        "cerveza": "🍺", "cervezas": "🍻", "vino": "🍷", "comida": "🍽️", "comer": "🍴", "hambre": "😋",
        "chocolate": "🍫", "helado": "🍦", "fresa": "🍓", "manzana": "🍎", "platano": "🍌", "pollo": "🍗",
        "pan": "🍞", "queso": "🧀", "huevo": "🥚", "taco": "🌮", "tacos": "🌮", "sushi": "🍣", "agua": "💧",
        "sueno": "😴", "dormir": "😴", "cansado": "😩", "cansada": "😩",
        "enfadado": "😠", "enfadada": "😠", "enojado": "😠", "enojada": "😠",
        "miedo": "😱", "susto": "😱", "omg": "😱", "sorpresa": "😮", "wow": "😮", "nervioso": "😬", "nerviosa": "😬",
        "pensando": "🤔", "duda": "🤔", "hmm": "🤔", "loco": "🤪", "loca": "🤪", "secreto": "🤫", "silencio": "🤫",
        "frio": "🥶", "calor": "🥵", "sol": "☀️", "lluvia": "🌧️", "nieve": "❄️", "playa": "🏖️", "mar": "🌊",
        "luna": "🌙", "noche": "🌙", "estrella": "⭐", "flor": "🌸", "flores": "💐",
        "casa": "🏠", "coche": "🚗", "carro": "🚗", "avion": "✈️", "viaje": "✈️", "vacaciones": "🌴", "tren": "🚆",
        "musica": "🎵", "cancion": "🎶", "cine": "🎬", "pelicula": "🎬", "juego": "🎮", "jugar": "🎮",
        "futbol": "⚽", "gol": "⚽", "baloncesto": "🏀", "gimnasio": "💪", "gym": "💪", "fuerza": "💪", "vamos": "💪",
        "gato": "🐱", "perro": "🐶", "libro": "📚", "estudiar": "📚", "examen": "📝", "trabajo": "💼",
        "telefono": "📱", "movil": "📱", "foto": "📷", "fotos": "📸", "ordenador": "💻", "correo": "📧",
        "hora": "⏰", "tarde": "⏰", "ojos": "👀", "mira": "👀", "bebe": "👶", "familia": "👪",
        "rey": "👑", "reina": "👑", "navidad": "🎄", "halloween": "🎃", "fantasma": "👻", "diablo": "😈", "angel": "😇",
        "cien": "💯", "verdad": "💯", "exito": "🏆", "ganar": "🏆", "campeon": "🏆", "suerte": "🍀",
        "enfermo": "🤒", "enferma": "🤒", "hospital": "🏥", "dolor": "🤕", "ayuda": "🆘", "peligro": "⚠️",
        "listo": "✅", "hecho": "✅", "error": "❌", "mal": "👎",
        "espana": "🇪🇸", "mexico": "🇲🇽", "argentina": "🇦🇷", "colombia": "🇨🇴", "chile": "🇨🇱", "peru": "🇵🇪"
    ]
}

/// Tonos de piel de los emojis de personas y manos, como al mantener pulsado en Gboard.
enum EmojiSkinTone {
    static let modifiers: [Unicode.Scalar] = [
        "\u{1F3FB}", "\u{1F3FC}", "\u{1F3FD}", "\u{1F3FE}", "\u{1F3FF}"
    ]

    /// Clave del emoji base, sin selector de variación ni tono.
    static func baseKey(_ emoji: String) -> String {
        String(String.UnicodeScalarView(emoji.unicodeScalars.filter {
            $0.value != 0xFE0F && !modifiers.contains($0)
        }))
    }

    static func supportsTones(_ emoji: String) -> Bool {
        let scalars = baseKey(emoji).unicodeScalars
        guard scalars.count == 1, let first = scalars.first else { return false }
        return first.properties.isEmojiModifierBase
    }

    /// El emoji original seguido de sus cinco tonos.
    static func variants(of emoji: String) -> [String] {
        guard supportsTones(emoji) else { return [emoji] }
        let base = baseKey(emoji)
        return [emoji] + modifiers.map { base + String($0) }
    }

    static let popular = Array(
        "😂❤️🤣👍😭🙏😘🥰😍😊🎉😁💕🥺😅🔥☺️🤦🙄😆🤗😉🎂🤔👏🙂😳😎💪✨"
    ).map(String.init)
}
