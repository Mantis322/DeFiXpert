using DotEnv
DotEnv.load!()

using Pkg
Pkg.activate(".")

using JuliaOSBackend.AlgoFiAPI

function main()
    @info "Starting server..."
    host = get(ENV, "HOST", "127.0.0.1")
    port = parse(Int, get(ENV, "PORT", "8052"))
    AlgoFiAPI.run_server(host, port)
    @info "Server started successfully on http://$(host):$(port)"
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end