#!/usr/bin/env python3
"""Gera summary.txt (medias por fluxo) e graficos PNG a partir dos .gr de um cenario.
Uso: python3 plot.py results/<cenario>/
Funciona sem matplotlib (so escreve o resumo)."""
import glob, os, sys

NOS = {0: "Cli1", 1: "Cli2", 2: "Cli3", 3: "E1", 4: "C0", 5: "E2", 6: "Cli4", 7: "Cli5", 8: "Cli6"}


def nome_fluxo(chave):
    # chave = "0.0_8.0" (no.porta origem _ no.porta destino)
    try:
        o, d = chave.split("_")
        no_o, p_o = o.split(".")
        no_d, p_d = d.split(".")
        return f"{NOS.get(int(no_o), no_o)}->{NOS.get(int(no_d), no_d)} ({o}->{d})"
    except ValueError:
        return chave


def ler(f):
    pts = []
    with open(f) as fh:
        for linha in fh:
            p = linha.split()
            if len(p) == 2:
                pts.append((float(p[0]), float(p[1])))
    return pts


def series(d, prefixo):
    out = {}
    for f in sorted(glob.glob(os.path.join(d, prefixo + "*.gr"))):
        base = os.path.basename(f)[:-3]
        if base == prefixo:
            out["TOTAL"] = ler(f)
        elif base.startswith(prefixo + "_"):
            out[nome_fluxo(base[len(prefixo) + 1:])] = ler(f)
    return out


def media(pts, a, b):
    v = [y for t, y in pts if a < t <= b + 0.5]
    return sum(v) / len(v) if v else 0.0


def main():
    d = sys.argv[1]
    cen = os.path.basename(os.path.normpath(d))
    if cen.startswith("C4"):   # fases do cenario C.4 (arranques em 0, 5 e 10 s)
        fases = [(1, 5, "so Cli1 (1-5s)"), (6, 10, "Cli1+Cli2 (6-10s)"), (11, 20, "os 3 (11-20s)")]
    else:
        fases = [(1, 15, "t=1-15s")]

    dados = {"loss": series(d, "loss"), "bw": series(d, "bw"), "bwE2": series(d, "bwE2")}
    linhas = [f"Cenario: {cen}"]
    for metrica, unid, esc in (("bw", "Mbps", 1e6), ("bwE2", "Mbps", 1e6), ("loss", "pkt/s", 1)):
        if not dados[metrica]:
            continue
        titulo = {"bw": "Largura de banda no link E1->C0", "bwE2": "Largura de banda no link E2->C0",
                  "loss": "Perdas (todos os links)"}[metrica]
        linhas.append(f"\n{titulo} [{unid}], media por fase")
        linhas.append("  " + "fluxo".ljust(36) + "".join(f[2].rjust(20) for f in fases))
        for k, pts in sorted(dados[metrica].items(), key=lambda x: (x[0] != "TOTAL", x[0])):
            linhas.append("  " + k.ljust(36) + "".join(f"{media(pts, a, b) / esc:20.3f}" for a, b, _ in fases))
    txt = "\n".join(linhas)
    with open(os.path.join(d, "summary.txt"), "w") as fh:
        fh.write(txt + "\n")
    print(txt)

    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        print("(matplotlib indisponivel: usar xgraph)")
        return
    for metrica, ylab, esc in (("bw", "Débito recebido em C0 vindo de E1 (Mbps)", 1e6),
                               ("bwE2", "Débito recebido em C0 vindo de E2 (Mbps)", 1e6),
                               ("loss", "Perdas (pacotes/s)", 1)):
        s = dados[metrica]
        if not s:
            continue
        fig, ax = plt.subplots(figsize=(6.4, 3.4))
        for k, pts in sorted(s.items(), key=lambda x: (x[0] != "TOTAL", x[0])):
            if not pts:
                continue
            t, y = zip(*pts)
            ax.plot(t, [v / esc for v in y], marker="o", ms=3,
                    lw=2.2 if k == "TOTAL" else 1.3, color="black" if k == "TOTAL" else None, label=k)
        ax.set_xlabel("Tempo (s)")
        ax.set_ylabel(ylab)
        ax.grid(alpha=0.3)
        ax.legend(fontsize=7, loc="best")
        fig.tight_layout()
        fig.savefig(os.path.join(d, f"{metrica}.png"), dpi=200)
        plt.close(fig)


if __name__ == "__main__":
    main()
