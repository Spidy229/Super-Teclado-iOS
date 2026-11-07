import Darwin
import Foundation
import os

/// Registrador de bloqueos: dice qué función tenía ocupado el teclado cuando se congela.
///
/// Un hilo aparte manda un aviso al hilo principal cada 50 ms. Si el principal tarda más de
/// 80 ms en atenderlo, lo detiene un instante, copia su pila de llamadas (las funciones que se
/// estaban ejecutando) y lo reanuda. Al terminar el bloqueo se guarda la pila con lo que duró y
/// sale en el informe de velocidad. Es lo que haría un depurador, pero en el propio iPhone.
final class MainThreadWatchdog: @unchecked Sendable {
    struct Freeze: Sendable {
        /// Milisegundos que el hilo principal estuvo sin responder.
        let milliseconds: Double
        /// Segundos desde que se abrió el teclado.
        let secondsSinceStart: Double
        /// Funciones de la pila, de la más interna (la que se ejecutaba) a la más externa.
        let frames: [String]
    }

    private struct State {
        var isRunning = false
        /// Cada arranque tiene su número: un hilo de un arranque anterior se para solo.
        var generation = 0
        var answered: UInt64 = 0
        var freezes: [Freeze] = []
    }

    static let shared = MainThreadWatchdog()

    /// A partir de cuánto se copia la pila y se apunta el bloqueo.
    private static let captureAfter: Double = 80
    private static let recordAfter: Double = 100
    private static let maxFrames = 48

    private let state = OSAllocatedUnfairLock(initialState: State())
    /// Hueco reservado de antemano: con el hilo principal detenido no se puede pedir memoria
    /// (podría tener el candado del gestor de memoria y se quedarían los dos esperando).
    private let frameBuffer = UnsafeMutablePointer<UInt>.allocate(capacity: MainThreadWatchdog.maxFrames)
    private var mainThread: thread_t = 0
    private var stackLow: UInt = 0
    private var stackHigh: UInt = 0
    private var startedAt: UInt64 = 0
    private var onFreeze: (@Sendable (Freeze) -> Void)?

    private init() {}

    /// Se llama desde el hilo principal al aparecer el teclado.
    @MainActor
    func start(onFreeze: @escaping @Sendable (Freeze) -> Void) {
        self.onFreeze = onFreeze
        let generation = state.withLock { state -> Int? in
            if state.isRunning { return nil }
            state.isRunning = true
            state.generation += 1
            return state.generation
        }
        guard let generation else { return }
        let thread = pthread_self()
        mainThread = pthread_mach_thread_np(thread)
        stackHigh = UInt(bitPattern: pthread_get_stackaddr_np(thread))
        stackLow = stackHigh &- UInt(pthread_get_stacksize_np(thread))
        startedAt = DispatchTime.now().uptimeNanoseconds
        let watcher = Thread { [self] in run(generation: generation) }
        watcher.name = "SuperTeclado.watchdog"
        watcher.qualityOfService = .userInteractive
        watcher.start()
    }

    func stop() {
        state.withLock { $0.isRunning = false }
    }

    /// Últimos bloqueos, del más reciente al más antiguo.
    var freezes: [Freeze] {
        state.withLock { $0.freezes }
    }

    private func isRunning(_ generation: Int) -> Bool {
        state.withLock { $0.isRunning && $0.generation == generation }
    }

    private func run(generation: Int) {
        while isRunning(generation) {
            let sent = DispatchTime.now().uptimeNanoseconds
            let token = sent
            let state = self.state
            DispatchQueue.main.async { state.withLock { $0.answered = token } }
            var captured: [UInt]?
            while true {
                usleep(10_000)
                let answered = state.withLock { $0.answered }
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds &- sent) / 1_000_000
                if answered == token {
                    if let captured, elapsed >= Self.recordAfter {
                        record(milliseconds: elapsed, sent: sent, addresses: captured)
                    }
                    break
                }
                if captured == nil, elapsed >= Self.captureAfter {
                    captured = captureMainStack()
                }
                guard isRunning(generation) else { return }
            }
            usleep(40_000)
        }
    }

    private func record(milliseconds: Double, sent: UInt64, addresses: [UInt]) {
        let freeze = Freeze(
            milliseconds: milliseconds,
            secondsSinceStart: Double(sent &- startedAt) / 1_000_000_000,
            frames: addresses.map(Self.describe)
        )
        state.withLock { state in
            state.freezes.insert(freeze, at: 0)
            if state.freezes.count > 4 { state.freezes.removeLast(state.freezes.count - 4) }
        }
        onFreeze?(freeze)
    }

    /// Detiene el hilo principal, copia su pila y lo reanuda. Entre medias solo se leen registros
    /// y memoria de su pila, sin pedir memoria ni candados.
    private func captureMainStack() -> [UInt] {
        #if arch(arm64)
        guard mainThread != 0, thread_suspend(mainThread) == KERN_SUCCESS else { return [] }
        var count = 0
        // arm_thread_state64_t: x0…x28, fp, lr, sp, pc, cpsr y relleno (272 bytes).
        var registers = (
            UInt64(0), UInt64(0), UInt64(0), UInt64(0), UInt64(0), UInt64(0), UInt64(0), UInt64(0),
            UInt64(0), UInt64(0), UInt64(0), UInt64(0), UInt64(0), UInt64(0), UInt64(0), UInt64(0),
            UInt64(0), UInt64(0), UInt64(0), UInt64(0), UInt64(0), UInt64(0), UInt64(0), UInt64(0),
            UInt64(0), UInt64(0), UInt64(0), UInt64(0), UInt64(0), UInt64(0), UInt64(0), UInt64(0),
            UInt64(0), UInt64(0)
        )
        var stateCount = mach_msg_type_number_t(68)
        let result = withUnsafeMutableBytes(of: &registers) { raw -> kern_return_t in
            let words = raw.baseAddress!.assumingMemoryBound(to: natural_t.self)
            return thread_get_state(mainThread, thread_state_flavor_t(6), words, &stateCount)
        }
        if result == KERN_SUCCESS {
            let (fpValue, lrValue, pcValue) = withUnsafeBytes(of: &registers) { raw in
                (
                    raw.load(fromByteOffset: 232, as: UInt64.self),
                    raw.load(fromByteOffset: 240, as: UInt64.self),
                    raw.load(fromByteOffset: 256, as: UInt64.self)
                )
            }
            frameBuffer[0] = UInt(pcValue) & Self.addressMask
            frameBuffer[1] = UInt(lrValue) & Self.addressMask
            count = 2
            var frame = UInt(fpValue)
            while count < Self.maxFrames,
                  frame >= stackLow, frame &+ 16 <= stackHigh, frame % 8 == 0,
                  let pointer = UnsafeRawPointer(bitPattern: frame) {
                let previous = pointer.load(as: UInt.self)
                let returnAddress = pointer.load(fromByteOffset: 8, as: UInt.self) & Self.addressMask
                if returnAddress == 0 { break }
                frameBuffer[count] = returnAddress
                count += 1
                // Cada marco anterior está más arriba en la pila.
                guard previous > frame else { break }
                frame = previous
            }
        }
        thread_resume(mainThread)
        return Array(UnsafeBufferPointer(start: frameBuffer, count: count))
        #else
        return []
        #endif
    }

    /// Quita la firma de los punteros (PAC) que llevan las direcciones de retorno en iOS.
    private static let addressMask: UInt = 0x0000_000F_FFFF_FFFF

    /// «Biblioteca  función + desplazamiento» para una dirección.
    private static func describe(_ address: UInt) -> String {
        var info = Dl_info()
        guard let pointer = UnsafeRawPointer(bitPattern: address), dladdr(pointer, &info) != 0 else {
            return String(format: "? 0x%lx", address)
        }
        let image = info.dli_fname.map { String(cString: $0) }.map { ($0 as NSString).lastPathComponent } ?? "?"
        if let name = info.dli_sname, let start = info.dli_saddr {
            let offset = address &- UInt(bitPattern: start)
            return "\(image)  \(String(cString: name)) + \(offset)"
        }
        let base = info.dli_fbase.map { UInt(bitPattern: $0) } ?? 0
        return String(format: "%@  0x%lx", image, address &- base)
    }

    /// La función más reveladora de la pila: la primera que no es de la espera del sistema.
    static func culprit(of freeze: Freeze) -> String {
        let boring = ["libsystem_kernel", "libsystem_pthread", "libsystem_platform", "libdyld"]
        let frame = freeze.frames.first { frame in !boring.contains { frame.hasPrefix($0) } }
            ?? freeze.frames.first
            ?? "?"
        return frame.count > 90 ? String(frame.prefix(90)) + "…" : frame
    }
}
