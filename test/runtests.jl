using Pkg
Pkg.activate("ReTest")
Pkg.develop(PackageSpec(path="../InlineTest"))

using ReTest

RUN = []

function check(x...; runtests=false, verbose=true, stats=false, dry=false)
    args = x[1:end-1]
    expected = x[end]
    if expected isa AbstractString
        expected = split(x[end])
    end

    empty!(RUN)
    if runtests
        getfield(args[1], :runtests)(args[2:end]...; verbose=verbose, stats=stats, dry=dry)
    else
        retest(args...; verbose=verbose, stats=stats, dry=dry)
    end
    @test RUN == expected
end

module M
using ReTest

RUN = []

@testset "a" begin
    push!(RUN, "a")
    @test true
end

@testset "b$i" for i=1:2
    push!(RUN, "b$i")
    @test true
end

@testset verbose=true "c" begin
    push!(RUN, "c")
    @test true

    @testset "d" begin
        push!(RUN, "d")
        @test true
    end

    @testset "e$i" for i=1:2
        push!(RUN, "e$i")
        @test true
    end
end

@testset "f$i" verbose=true for i=1:1
    push!(RUN, "f$i")
    @test true

    @testset "g" begin
        push!(RUN, "g")
        @test true
    end

    @testset "h$i" for i=1:2
        push!(RUN, "h$i")
        @test true
    end
end

innertestsets = ["d", "e1", "e2", "g", "h1", "h2"]

function check(rx, list)
    empty!(RUN)
    retest(M, Regex(rx))
    @test RUN == list
    mktemp() do path, io
        redirect_stdout(io) do
            retest(M, Regex(rx), dry=true, id=false) # TODO: test with id=true
        end
        seekstart(io)
        expected = map(list) do t
            if t in innertestsets
                "  " * t
            else
                t
            end
        end
        expected = join(expected, '\n')
        actual = readchomp(io)
        if isempty(expected)
            @test startswith(actual, "No matching tests for module")
        else
            @test actual == expected
        end
    end
end
end

# we don't put these checks in a @testset, as this would modify filtering logic
# (e.g. with `@testset "filtering" ...`, testset subjects would start with "/filtering/...")
M.check("a", ["a"])
M.check("a1", []) # testset is "final", so we do a full match
M.check("b", ["b1", "b2"])
M.check("/b", ["b1", "b2"])
M.check("b1", ["b1"])
M.check("c1", []) # "c1" is *not* partially matched against "/c/"
M.check("c/1", []) # "c" is partially matched, but nothing fully matches afterwards
M.check("c/d1", [])
M.check("c/d", ["c", "d"])
M.check("/c", ["c", "d", "e1", "e2"])
M.check(".*d", ["c", "d"])
M.check(".*(e1|e2)", ["c", "e1", "e2"])
M.check("f1", ["f1", "g", "h1", "h2"])
M.check("f",  ["f1", "g", "h1", "h2"])
M.check(".*g", ["f1", "g"])
M.check(".*h", ["f1", "h1", "h2"])
M.check(".*h1", ["f1", "h1"])
M.check(".*h\$", [])

# by default, respect order of tests:
M.check("", ["a", "b1", "b2", "c", "d", "e1", "e2", "f1", "g", "h1", "h2"])
retest(M)

module N
using ReTest
using Main: RUN

# testing non-final non-toplevel testsets
@testset "i" begin
    push!(RUN, "i")
    @test true

    @testset "j" verbose=false begin # false, just to test that it works
        push!(RUN, "j")
        @test true

        @testset "k" begin
            push!(RUN, "k")
            @test true
        end
    end

    @testset "l$i" verbose=true for i=1:1
        push!(RUN, "l$i")
        @test true

        @testset "m" begin
            push!(RUN, "m")
            @test true
        end
    end
end
end # N

check(N, r".*j1", ""; runtests=true)
check(N, r".*j/1", ""; runtests=false)
check(N, r"^/i/j0", ""; runtests=true)
check(N, r"^/i/l10", ""; runtests=false)

### module P #################################################################
# test ReTest's wrapping of non-regex patterns

module P
using ReTest
using Main: RUN

# testing non-final non-toplevel testsets
@testset "a" begin
    push!(RUN, "a")
    @test true

    @testset "b" begin
        push!(RUN, "b")
        @test true
    end

    @testset "b|c" begin
        push!(RUN, "b|c")
        @test true
    end
end

@testset "D&E" begin
    push!(RUN, "D&E")
    @test true
end
end # P

check(P, "b", "a b b|c"; verbose=2) # an implicit prefix r".*" is added
check(P, "B", "a b b|c"; verbose=0, runtests=true) # idem, case-insensitive
check(P, r"B", "") # not case-insensitive

if VERSION >= v"1.3"
    check(P, "b|c", "a b|c") # "b" is not matched
    check(P, "B|C", "a b|c") # idem, case-insensitive
end

check(P, "d&e", "D&E")
check(P, "d&E", "D&E")
check(P, r"d&E", "")
check(P, r"d&E"i, "D&E")


### multiple patterns ########################################################

module MultiPat
using ReTest
using Main: RUN

@testset "a" begin
    push!(RUN, "a")

    @testset "b" begin
        push!(RUN, "b")
    end
end

@testset "aa" begin
    push!(RUN, "aa")
end

@testset "b" begin
    push!(RUN, "c")
end

@testset "d$i" for i=1:2
    push!(RUN, "d$i")
end

end # MultiPat

check(MultiPat, "a", "a b aa")
check(MultiPat, "b", "a b c")
check(MultiPat, "a", "b", "a b")
check(MultiPat, ("a", "b"), "a b")
check(MultiPat, "b", r"a", "a b")
check(MultiPat, "b", "d", "")
check(MultiPat, "a", "e", "")
check(MultiPat, ["aa", "2"], "aa d2")
check(MultiPat, ["1", "2"], "d1 d2")
check(MultiPat, ["aa", "2"], "d", "d2")
check(MultiPat, ["aa", "2", ["2", "1"]], "d", "d1 d2")

# with integers
# check we don't collect the range:
check(MultiPat, 1:Int64(10)^15, "a b aa c d1 d2")
check(MultiPat, 5, "d1 d2")
check(MultiPat, "a", 2:3, "a b aa")
check(MultiPat, "a", 1:2, "a b")
check(MultiPat, "a", [1, 3], "a aa")
check(MultiPat, ["aa", 4], "aa c")


### Module patterns ##########################################################

module ModPat
using ReTest
using Main: RUN

@testset "aa" begin
    push!(RUN, "aa")
    @testset "b" begin
        push!(RUN, "b")
    end
end

@testset "ab" begin
    push!(RUN, "ab")
end

module In
module Ner
using ReTest
using Main: RUN

@testset "c" begin
    push!(RUN, "c")
end
end end # In.Ner
end # ModPat

module ModPat2
using ReTest
using Main: RUN

@testset "ad" begin
    push!(RUN, "ad")
end
end

check(ModPat, "aa b ab c")
check(ModPat => 1:99, "aa b ab") # no recursive
check(ModPat => "a", 1:2, "aa b")
check(ModPat2 => "a", ModPat, 1:9, "ad aa b ab c") # ModPat recursive
check(ModPat2 => ("a", 1:9), ModPat => 1:9, "ad aa b ab") # ModPat not recursive
check(ModPat2 => "a", ModPat, 2:9, "aa b ab")
check(ModPat2 => "a", ModPat, ModPat, 2:9, "aa b ab") # deduplicate
check(ModPat2 => "", ModPat => "aa", 2, "aa b")

### toplevel #################################################################

# The following test is just to exert `@assert allunique(TESTED_MODULES)` in
# computemodules!, and must be run before any toplevel @testset in declared,
# so that `Main` is not yet in TESTED_MODULES; we check that previous
# tested modules, which are in submodules of Main, are not re-added to
# TESTED_MODULES while going through submodules of Base.loaded_modules ∋ Main
retest(dry=true)
RUNTOP = []
@testset "toplevel" begin
    # this tests that the testset is run exactly once
    # Main is special here, as it's both in Base.loaded_modules
    # and it gets registered automatically in ReTest.TESTED_MODULES
    push!(RUNTOP, "toplevel")
    @test true
end

retest(verbose=Inf)
retest("a", shuffle=true, stats=true)
retest(M, N, P, "b", dry=true)

for v in (-rand(1:9), 4.2, -Inf)
    @test_throws ArgumentError retest(verbose=v)
end

@test RUNTOP == ["toplevel"]

retest(r"^/f1", stats=true) # just test that a regex can be passed,
                            # and that stats works for multiple subtests

empty!(RUN)

module Overwritten
using ReTest
import Main: RUN
@testset "first" begin
    push!(RUN, 1)
end
end
check(Overwritten, [1]; stats=true) # testing stats when there are not tests

module Overwritten
using ReTest
import Main: RUN
@testset "second" begin
    push!(RUN, 2)
end
end
check(Overwritten, [2])
# 1 must not appear (i.e. ReTest must not keep a reference to
# the old overwritten version of `Overwritten`

### Loops ####################################################################

module Loops1
using ReTest
using Main: RUN

@testset "loops 1" begin
    push!(RUN, 9)
    a = 1
    b = 2

    @testset "local$i" for i in (a, b)
        push!(RUN, i)
        @test true
        @testset "sub" begin
            push!(RUN, 0)
            @test true

            @testset "final" begin
                @test true
                push!(RUN, -1)
            end
        end
    end
end
end

# @test_logs (:warn, r"could not evaluate testset description.*") retest(Loops1, r"asd")
# @test Loops1.RUN == [1, 0, 2, 0]
# empty!(Loops1.RUN)
# retest(Loops1) # should not log
check(Loops1, [9, 1, 0, -1, 2, 0, -1])
check(Loops1, 9:9, []) # when no regex is passed, even with the presence of statically
                       # unresolvable descriptions, we can filter out stuff
                       # (i.e. here, we don't run "loops 1" just in case "local$i" would
                       # be run, as we can determine from pattern 9:9 that nothing must run)

module Loops2
using ReTest
using Main: RUN

@testset "loops 2" begin
    @testset "generator $i $I" for (i, I) in (i => typeof(i) for i in (1, 2))
        push!(RUN, i)
        @test true
        @testset "sub" begin
            push!(RUN, 0)
            @test true

            @testset "final" begin
                @test true
                push!(RUN, -1)
            end
        end
    end
end
end

# the test below has been solved
# TODO: check whether another run could lead to the same result, i.e. RUN == [1, 0, 2, 0] ?
# @test_logs (:warn, r"could not evaluate testset-for iterator.*") retest(Loops2, r"asd")
# @test Loops2.RUN == [1, 0, 2, 0]

check(Loops2, [1, 0, -1, 2, 0, -1])

module Loops3
using ReTest
using Main: RUN

@testset "loops 3" begin
    @testset "generator $i $I" for (i, I) in [i => typeof(i) for i in (1, 2)]
        push!(RUN, i)
        @test true
        @testset "sub" begin
            push!(RUN, 0)
            @test true

            @testset "final" begin
                @test true
                push!(RUN, -1)
            end
        end
    end
end
end

check(Loops3, r"asd", [])
check(Loops3, [1, 0, -1, 2, 0, -1])

module MultiLoops
using ReTest
using Main: RUN

C1, C2 = 1:2 # check that iteration has access to these values

@testset "multiloops $x $y $z" for (x, y) in zip(1:C2, 1:2), z in C1:x
    push!(RUN, (x, z))
    @test true
end
end

check(MultiLoops, [(1, 1), (2, 1), (2, 2)])
check(MultiLoops, "1 1", [(1, 1)])

module Anonym
using ReTest
using Main: RUN

@testset for x=1:2
    @testset begin
        @test true
        push!(RUN, x)
    end
end
end

check(Anonym, [1, 2])

### loop variable collision ##################################################

module LoopCollision
using ReTest
using Main: RUN

@assert isdefined(LoopCollision, :sincos)
@assert isdefined(LoopCollision, :sinpi)

@testset "collision $sincos" for sincos in (sin, cos)
    @test sincos(1.0) isa Float64
    push!(RUN, sincos)
end

@testset "collision $sincos sinpi $sinpi" for sincos = (sin, cos), sinpi = (1,)
    @test true
    push!(RUN, (sincos, sinpi))
end

end # LoopCollision

retest(LoopCollision, dry=true)
check(LoopCollision, [sin, cos, (sin, 1), (cos, 1)]; dry=false)


### interpolated description #################################################

module Interpolate
using ReTest
using Main: RUN

X = 0

@testset "a $X" verbose=true begin
    @testset "b $X" begin
        @test true
        push!(RUN, 1)
    end
    @testset "c $X $i" for i=2:3
        @test true
        push!(RUN, i)
    end
end

@testset "d $X $i" verbose=true for i=4:4
    @test true
    push!(RUN, i)
    @testset "e $X" begin
        @test true
        push!(RUN, 5)
    end
end
end # Interpolate

retest(Interpolate, dry=true)
check(Interpolate, 1:5)

check(Interpolate, "0", 1:5)

check(Interpolate, "4", 4:5)

module InterpolateImpossible
using ReTest
using Main: RUN

X = 0

@testset "a $X" verbose=true begin
    j = 9
    @testset "b $X $j" begin
        @test true
        push!(RUN, 1)
    end
    @testset "c $X $j $i" for i=2:3
        @test true
        push!(RUN, i)
    end
end

@testset "d $X $i" verbose=true for i=4:4
    @test true
    push!(RUN, i)
    @testset "e $X $i" begin
        @test true
        push!(RUN, 5)
    end
    @testset "$i" begin # must work even "$i" is made only of Expr (no String parts)
        @test true
        push!(RUN, 6)
    end
end
end # InterpolateImpossible

retest(InterpolateImpossible, dry=true)
check(InterpolateImpossible, 1:6)
check(InterpolateImpossible, "0", 1:6)
check(InterpolateImpossible, "4", 4:6) # should have a warning or two


### Failing ##################################################################

module Failing
using ReTest

@testset "has fails" begin
    @test false
end
end

@test_throws Test.TestSetException retest(Failing)

### Duplicate ################################################################

module Duplicate
using ReTest

RUN = []

@testset "dupe" begin
    @test true
    push!(RUN, 1)
end
@testset "dupe" begin
    @test true
    push!(RUN, 2)
end

@testset "dupe$i" for i=3:4
    @test true
    push!(RUN, i)
end
@testset "dupe$i" for i=5:6
    @test true
    push!(RUN, i)
end
end

@test_logs (
    :warn, r"duplicate description for @testset, overwriting:.*") (
    :warn,  r"duplicate description for @testset, overwriting:.*")  Duplicate.runtests()
@test Duplicate.RUN == [2, 5, 6]

### Uniquify #################################################################

empty!(Duplicate.RUN)

retest(Duplicate, Duplicate, "dupe5")
@test Duplicate.RUN == [5]

### Display ##################################################################

# we exercise a bunch of codepaths, and this allows to have an idea whether
# everything prints properly (writing proper display tests will be soooo boring)

module X
using ReTest

@testset "X.full" begin
    @test true
    @testset "X.inner" begin
    end
end
end

module YYYYYYYYYYYYY
using ReTest

@testset "Y.broken" begin
    @testset "hidden" begin
        # we "hide" it to be sure that the .hasbrokenrec field is used and not .hasbroken
        @test_broken false
    end
end
@testset "Y.loop $('*'^(10-3*i))" for i=1:2
    @test true
    @testset "Y.inner_____________" begin
        @test true
        @testset "Y.core" begin
            @test true
        end
    end
end
end

module NoTests
using ReTest

@testset "empty" begin end
@testset "empty $i" for i=1:1 end
end

for dry=(true, false),
    verbose=0:3,
    stats=(true, false),
    mod=((X,), (YYYYYYYYYYYYY,), (X, YYYYYYYYYYYYY), (NoTests,)),
    pattern=(r"inner", 1:99, "not matching")

    id=rand([true, false, nothing])
    if pattern == "not matching"
        mod in [(X,), (X, YYYYYYYYYYYYY)] || continue
        verbose in 0:1 || continue
    end
    if mod == (NoTests,)
        dry == false && verbose in 0:1 && pattern == 1:99 ||
            continue
    end
    modstr = length(mod) == 1 ? string(mod[1]) : string(mod)
    # have to show 'X' below, because `nothing` can't be printed on old Julia
    println("\n####################### Display: mod=$modstr stats=$stats dry=$dry verbose=$verbose pattern=$pattern, id=$(something(id, 'X'))\n")
    retest(mod..., pattern; shuffle=true, verbose=verbose, stats=stats, dry=dry, id=id)
end

### dry-run

module DryRun
using ReTest

X = 'a'

@testset "a" for i=1:2
    @testset "b" begin end
end
@testset "a$X" for i=1:2
    @testset "b" begin end
end
@testset "x$i" for i=1:2
    @testset "b$i" begin
        @testset "c" begin end
    end
    @testset "d$i$j" for j=1:2
    end
end
@testset "y$i" for i=1:1
    @testset "b" for j=1:i
        @testset "c" begin end
    end
end

end # DryRun

retest(DryRun, dry=true)
retest(DryRun, dry=true, verbose=0)
retest(DryRun, dry=true, verbose=5)

module DryRun2
using ReTest

@testset "just a dummy module" begin end
end # DryRun2

retest(DryRun, DryRun2, dry=true, verbose=0)
retest(DryRun, DryRun2, dry=true, verbose=1)

### InlineTest ###############################################################

using Pkg
Pkg.activate("./FakePackage")
Pkg.develop(PackageSpec(path="../InlineTest"))
Pkg.develop(PackageSpec(path="..")) # ReTest
Pkg.test("FakePackage")

### Hijack ###################################################################

Pkg.activate("./Hijack")
Pkg.develop(PackageSpec(path="..")) # ReTest
Pkg.test("Hijack")

if VERSION >= v"1.5"

    using Hijack
    ReTest.hijack(Hijack)
    retest(HijackTests)
    @test Hijack.RUN == [1]
    empty!(Hijack.RUN)

    @test_throws ErrorException ReTest.hijack(Hijack, :HijackTests2, revise=true)

    using Revise
    ReTest.hijack(Hijack, :HijackTests2, revise=true)
    retest(HijackTests2)
    @test Hijack.RUN == [1]
    empty!(Hijack.RUN)

    cp("./Hijack/test/subdir/sub.jl",
       "./Hijack/test/subdir/sub.orig.jl", force=true)

    write("./Hijack/test/subdir/sub.jl",
          """
@test true

@testset "sub" begin
    @test true
    @test true
    push!(Hijack.RUN, 2)
end
""")
    Revise.revise()
    try
        retest(HijackTests2)
        @test Hijack.RUN == [2]
    finally
        mv("./Hijack/test/subdir/sub.orig.jl",
           "./Hijack/test/subdir/sub.jl", force=true)
    end
end
