import sys
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import reduce_system as rs  # noqa: E402

EXAMPLE = "1,x,x2,2,1,1x2,1,x,1,2,1x,1,1x"


def read_rows(path: Path) -> list[list[str]]:
    lines = path.read_text().splitlines()
    assert lines[0] == "Stryktipset"
    rows = []
    for line in lines[1:]:
        parts = line.split(",")
        assert parts[0] == "E" and len(parts) == 14
        rows.append(parts[1:])
    return rows


def best_hits(entries: list[str], rows: list[list[str]]) -> int:
    """Worst case over all outcomes of the best row's correct count."""
    fs = rs.FullSystem.build(entries)
    worst = 13
    for i in range(fs.size):
        outcome = fs.row_signs(i)
        best = max(sum(a == b for a, b in zip(outcome, r)) for r in rows)
        worst = min(worst, best)
    return worst


def test_parse_normalises():
    assert rs.parse_system(EXAMPLE)[:3] == ["1", "X", "X2"]
    assert rs.parse_system("2x1," * 12 + "x")[0] == "1X2"


@pytest.mark.parametrize("text", ["1,2", EXAMPLE + ",1", EXAMPLE[:-1] + "y",
                                  EXAMPLE.replace("x2", "xx"), "," + EXAMPLE[2:]])
def test_parse_rejects(text):
    with pytest.raises(ValueError):
        rs.parse_system(text)


def test_neighbour_table_matches_hamming():
    fs = rs.FullSystem.build(rs.parse_system(EXAMPLE))
    nbr, n1 = rs.neighbour_table(fs, 2)
    for i in range(fs.size):
        d = (fs.digits != fs.digits[i]).sum(axis=1)
        assert set(nbr[i]) == set(np.flatnonzero(d <= 2))
        assert all(d[j] == 1 for j in nbr[i, 1:1 + n1])


@pytest.mark.parametrize("guarantee", [10, 11, 12, 13])
@pytest.mark.parametrize("algorithm", ["greedy", "anneal"])
def test_guarantee_holds(tmp_path, guarantee, algorithm):
    out = tmp_path / "out.txt"
    rc = rs.main([EXAMPLE, "-g", str(guarantee), "-a", algorithm, "--seed", "1",
                  "-i", "2000", "-q", "-o", str(out)])
    assert rc == 0
    rows = read_rows(out)
    assert best_hits(rs.parse_system(EXAMPLE), rows) >= guarantee


def test_ternary_hamming_code_found(tmp_path):
    # 4 full matches, guarantee 12: the perfect ternary Hamming code, 9 rows.
    system = "1x2,1x2,1x2,1x2," + ",".join(["1"] * 9)
    out = tmp_path / "out.txt"
    assert rs.main([system, "-g", "12", "-a", "anneal", "--seed", "3",
                    "-q", "-o", str(out)]) == 0
    assert len(read_rows(out)) == 9


def test_max_rows_limits_output(tmp_path):
    out = tmp_path / "out.txt"
    system = "1x2,1x2,1x2,1x2,1x2,1x,1x,x2,1,1,1,1,1"
    assert rs.main([system, "-g", "12", "-n", "20", "--seed", "1", "-q",
                    "-o", str(out)]) == 0
    assert len(read_rows(out)) == 20


def test_single_row(tmp_path):
    out = tmp_path / "out.txt"
    assert rs.main(["1,x,2,1,x,2,1,x,2,1,x,2,1", "-q", "-o", str(out)]) == 0
    assert read_rows(out) == [list("1X21X21X21X21")]


def test_bad_input_returns_error(tmp_path):
    assert rs.main(["1,2", "-q", "-o", str(tmp_path / "x.txt")]) == 2


@pytest.mark.parametrize("k", [1, 3, 6, 15, 24])
@pytest.mark.parametrize("guarantee", [11, 12, 13])
def test_fixed_rows_exact_count(tmp_path, k, guarantee):
    out = tmp_path / "out.txt"
    assert rs.main([EXAMPLE, "-g", str(guarantee), "-k", str(k), "--seed", "1",
                    "-q", "-o", str(out)]) == 0
    rows = read_rows(out)
    assert len(rows) == k
    assert len({tuple(r) for r in rows}) == k  # no duplicate rows


def test_fixed_rows_keeps_guarantee_when_padding(tmp_path):
    out = tmp_path / "out.txt"
    assert rs.main([EXAMPLE, "-g", "11", "-k", "10", "--seed", "2", "-q",
                    "-o", str(out)]) == 0
    assert best_hits(rs.parse_system(EXAMPLE), read_rows(out)) >= 11


def test_fixed_rows_partial_with_anneal(tmp_path):
    out = tmp_path / "out.txt"
    system = "1x2,1x2,1x2,1x2,1x2,1x,1x,x2,1,1,1,1,1"
    assert rs.main([system, "-g", "12", "-k", "40", "-a", "anneal",
                    "-i", "3000", "--seed", "1", "-q", "-o", str(out)]) == 0
    assert len(read_rows(out)) == 40


def test_fixed_rows_too_many(tmp_path):
    assert rs.main([EXAMPLE, "-k", "25", "-q",
                    "-o", str(tmp_path / "x.txt")]) == 2


def test_rows_and_max_rows_exclusive(tmp_path):
    with pytest.raises(SystemExit):
        rs.main([EXAMPLE, "-k", "5", "-n", "5", "-o", str(tmp_path / "x.txt")])


def test_default_filename_shows_criteria(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    assert rs.main([EXAMPLE, "-g", "11", "-k", "5", "--seed", "7", "-q"]) == 0
    name = "stryktipset_1-X-X2-2-1-1X2-1-X-1-2-1X-1-1X_g11_k5_greedy_s7.txt"
    assert len(read_rows(tmp_path / name)) == 5


def test_output_directory_gets_automatic_name(tmp_path):
    assert rs.main([EXAMPLE, "-n", "3", "-a", "anneal", "-i", "100", "-q",
                    "-o", str(tmp_path)]) == 0
    files = list(tmp_path.iterdir())
    assert [f.name for f in files] == [
        "stryktipset_1-X-X2-2-1-1X2-1-X-1-2-1X-1-1X_g12_n3_anneal.txt"]


def test_summary_on_stdout_only(tmp_path, capsys):
    out = tmp_path / "out.txt"
    assert rs.main([EXAMPLE, "-g", "12", "--seed", "1", "-o", str(out)]) == 0
    captured = capsys.readouterr()
    assert "Rows written:  6" in captured.out
    assert f"Output file:   {out}" in captured.out
    assert captured.err == ""
