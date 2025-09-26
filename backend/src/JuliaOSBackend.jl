module JuliaOSBackend

include("resources/Resources.jl")
include("agents/Agents.jl")
include("db/JuliaDB.jl")
include("api/JuliaOSV1Server.jl")
include("users/AlgoFiUsers.jl")
include("api/AlgoFiAPI.jl")
include("api/AIStrategyAPI.jl")

using .Resources
using .Agents
using .JuliaDB
using .JuliaOSV1Server
using .AlgoFiUsers
using .AlgoFiAPI
using .AIStrategyAPI

end