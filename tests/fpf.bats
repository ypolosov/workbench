#!/usr/bin/env bats
# The practice of the workbench rests on FPF: its skills, hooks and texts carry neither
# code nor text of the earlier IWE template, stages of work have their own skill, and
# every FPF address of the practice exists in the pinned edition.

load helpers

@test "в практике шаблона нет наследия IWE" {
  bad="$(cd "$ROOT" && {
    # Section 7 of AGENTS.md holds the owner's own rules: they may name anything.
    awk '/^## 7\./ { exit } { print "AGENTS.md:" FNR ":" $0 }' AGENTS.md
    git ls-files -co --exclude-standard -z -- README.md lpf/README.md install.sh Makefile \
      .agents/skills scripts adapters/claude/hooks .githooks bin .github |
      xargs -0 grep -Hn ''
  } | grep -E 'IWE|FMT-exocortex|Tserenov|(^|[^a-z])vdv([^a-z]|$)|DP\.SC\.|PD\.METHOD|Day Open|ВДВ' |
    # The owner may still ask for stages by the old name of the method.
    grep -vE '^\.agents/skills/stages/SKILL\.md:[0-9]+:.*ВДВ' || true)"
  [ -z "$bad" ] || {
    echo "наследие IWE:"
    echo "$bad"
    return 1
  }
}

@test "есть скилл этапов работы" {
  [ -f "$ROOT/.agents/skills/stages/SKILL.md" ]
}

@test "каждый ID FPF в текстах практики есть в закреплённом издании" {
  # A base has the pinned edition in .fpf (scripts/setup.sh), CI fetches it for the
  # template; a plain clone has nothing to compare with.
  pinned="$(sed -n 's/^commit=//p' "$ROOT/.fpf-edition" | tail -n 1)"
  [ "$(git -C "$ROOT/.fpf" rev-parse HEAD 2>/dev/null)" = "$pinned" ] ||
    skip "в .fpf нет закреплённого издания FPF"
  # Every pattern and section of FPF and its DPFs is a heading that starts with its ID.
  git -C "$ROOT/.fpf" grep -h -o -E '^#{2,6} [A-Z][A-Za-z0-9]*(\.[A-Za-z0-9]+)+(:[0-9A-Za-z.]+)?' -- '*.md' |
    sed -E 's/^#+ //' >"$BATS_TEST_TMPDIR/known"
  # A perl program, not shell text. Section 7 of AGENTS.md holds the owner's own rules,
  # and a local LPF or DPF declares its own IDs in its headings.
  # shellcheck disable=SC2016
  bad="$(cd "$ROOT" && git ls-files -co --exclude-standard -z -- AGENTS.md README.md \
    'lpf/*.md' 'dpf/*.md' '.agents/skills/*.md' | xargs -0 perl -e '
      my ($known, @files) = @ARGV;
      my $id = qr/[A-Z][A-Z0-9]*(?:\.[A-Z0-9]+)+(?::[0-9]+(?:\.[0-9]+)*[a-z]?)?/;
      my (%ok, %text);
      open my $k, "<", $known or die "$known: $!";
      while (<$k>) { s/\r?\n\z//; $ok{$_} = 1 }
      for my $f (@files) {
        open my $h, "<", $f or die "$f: $!";
        while (my $l = <$h>) {
          $l =~ s/\r?\n\z//;
          last if $f eq "AGENTS.md" && $l =~ /^## 7\./;
          push @{ $text{$f} }, $l;
          $ok{$1} = 1 if $l =~ /^#+ ($id)(?: |$)/;
        }
      }
      for my $f (@files) {
        my $n = 0;
        for my $l (@{ $text{$f} || [] }) {
          $n++;
          while ($l =~ /(?<![\w.])($id)(?!\w)/g) { print "$f:$n: $1\n" unless $ok{$1} }
        }
      }' "$BATS_TEST_TMPDIR/known")"
  [ -z "$bad" ] || {
    echo "нет в закреплённом издании FPF ${pinned:0:7}:"
    echo "$bad"
    return 1
  }
}
