import SwiftUI
import UIKit

/// Explica qué permite iOS y cómo guardar en el historial lo que se copia con el teclado cerrado.
struct ClipboardCaptureGuideView: View {
    var body: some View {
        Form {
            Section {
                Text("iOS solo deja que un teclado lea el portapapeles mientras está abierto. Si copias varias cosas con el teclado cerrado, al abrirlo solo verá la última. Estas son todas las formas de no perder nada:")
                    .font(.callout)
            }

            Section {
                step("keyboard", "Con el teclado abierto", "Todo lo que copies (textos, enlaces e imágenes, también varios a la vez) entra solo en Recientes.")
                step("square.and.arrow.up", "Compartir › Super Teclado", "En cualquier app, toca Compartir y elige Super Teclado para guardar un texto, un enlace o fotos. Si no aparece, desliza los iconos hasta «Más» y actívalo.")
                step("app.badge", "Al abrir la app", "La app guarda lo que hay copiado cada vez que vuelves a ella.")
            } header: {
                Text("Automático")
            }

            Section {
                step("1.circle", "Crea el atajo", "Abre Atajos › + y añade «Obtener portapapeles» y después «Guardar en el portapapeles de Super Teclado» con el texto «Portapapeles».")
                step("2.circle", "Actívalo con el toque posterior", "Ajustes › Accesibilidad › Tocar › Toque posterior › Doble toque, y elige el atajo. Copia algo y da dos toques en la parte trasera del iPhone.")
                step("3.circle", "O con Siri", "Di «Guardar el portapapeles en Super Teclado». También tienes «Copiar lo último de Super Teclado».")
                Button {
                    if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
                } label: {
                    Label("Abrir Atajos", systemImage: "arrow.up.forward.app")
                }
            } header: {
                Text("Atajo con un toque")
            } footer: {
                Text("El atajo funciona sin abrir el teclado ni la app.")
            }

            Section {
                step("hand.raised", "Evita la pregunta de pegar", "En Ajustes › Super Teclado › Pegar desde otras apps, elige «Permitir» para que la app no pregunte cada vez.")
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Label("Abrir Ajustes", systemImage: "gear")
                }
            } header: {
                Text("Permisos")
            }

            Section {
                Text("Los teclados de iOS no pueden leer el portapapeles en segundo plano ni insertar imágenes directamente: las imágenes se copian para que las pegues manteniendo pulsado el campo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Límites de iOS")
            }
        }
        .navigationTitle("Guardar lo copiado")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ symbol: String, _ title: String, _ detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(.cyan)
        }
        .padding(.vertical, 2)
    }
}
