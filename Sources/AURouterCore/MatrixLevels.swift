import Foundation

public enum MatrixLevels {
    /// Builds the full AUMatrixMixer state: crosspoints, input gains, output gains, and global gain.
    public static func make(
        inputChannels: Int,
        outputChannels: Int,
        routes: [(input: Int, output: Int, gain: Float)]
    ) throws -> [Float] {
        guard inputChannels > 0, outputChannels > 0 else {
            throw AURouterError.invalidRoute("A matrix mixer needs at least one input and output channel.")
        }

        let columns = outputChannels + 1
        var levels = Array(repeating: Float(0), count: (inputChannels + 1) * columns)

        for route in routes {
            guard route.input >= 0,
                  route.input < inputChannels,
                  route.output >= 0,
                  route.output < outputChannels else {
                throw AURouterError.invalidRoute("A channel matrix route is out of bounds.")
            }
            levels[(route.input * columns) + route.output] = route.gain
        }

        for input in 0..<inputChannels {
            levels[(input * columns) + outputChannels] = 1
        }
        for output in 0..<outputChannels {
            levels[(inputChannels * columns) + output] = 1
        }
        levels[(inputChannels * columns) + outputChannels] = 1
        return levels
    }
}
