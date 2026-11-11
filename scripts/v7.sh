# Sourced by the build, test and release scripts. The v7 (7.x Worlds)
# client repros are not blocking until there is more v7 research
# (Squirrel, 2026-11-11; ROADMAP #154): a failing v7 build, test, pack or
# check prints a warning and the run goes on. V7_STRICT=1 makes them block
# again.
# Every Worlds folder is v7: graal-worlds-<build>-<date>.

# is_v7 FOLDER: true for a v7 client folder (a path or a bare name)
is_v7() {
  case "$(basename "$1")" in
    graal-worlds-*) return 0 ;;
  esac
  return 1
}

# v7_warn FOLDER WHAT: report a v7 failure without failing the run
v7_warn() {
  echo "::warning::$1 (v7, not blocking): $2"
}
