#############################
# @benchmark/@benchmarkable #
#############################

const DEFAULT_TIME_LIMIT = 5.0

macro benchmark(args...)
    tmp = gensym()
    return esc(quote
        $(tmp) = BenchmarkTools.@benchmarkable $(args...)
        BenchmarkTools.execute($(tmp), 1e-6) # precompile
        BenchmarkTools.execute($(tmp))
    end)
end

macro benchmarkable(args...)
    if length(args) == 1
        core = first(args)
        default_seconds = DEFAULT_TIME_LIMIT
    elseif length(args) == 2
        core, default_seconds = args
    else
        error("wrong number of arguments for @benchmark")
    end
    return esc(quote
        let
            _wrapfn = gensym("wrap")
            _trialfn = gensym("trial")
            eval(current_module(), quote
                @noinline $(_wrapfn)() = $($(Expr(:quote, core)))
                @noinline function $(_trialfn)(seconds::Float64)
                    time_limit::Float64 = isnan(seconds) ? $($(Expr(:quote, default_seconds))) : seconds
                    @assert time_limit > 0.0 "time limit must be greater than 0.0"
                    gc()
                    time_limit_ns = time_limit * 1e9
                    total_evals = 0.0
                    gc_start = Base.gc_num()
                    start_time = time_ns()
                    growth_rate = 1.01
                    iter_evals = 2.0
                    while (time_ns() - start_time) < time_limit_ns
                        for _ in 1:floor(iter_evals)
                            $(_wrapfn)()
                        end
                        total_evals += iter_evals
                        iter_evals *= growth_rate
                    end
                    elapsed_time = time_ns() - start_time
                    gcdiff = Base.GC_Diff(Base.gc_num(), gc_start)
                    bytes = gcdiff.allocd
                    allocs = gcdiff.malloc + gcdiff.realloc + gcdiff.poolalloc + gcdiff.bigalloc
                    gctime = gcdiff.total_time
                    return BenchmarkTools.Trial(total_evals, elapsed_time, gctime, bytes, allocs)
                end
            end)
        end
    end)
end
