"""Aplica a definicao do Genie space (src/genie/genie_space.json) no workspace.

Substitui ${catalogo} e ${schema_gold} pelos valores passados e cria ou atualiza
o space pelo titulo — iteracao sobre o JSON fica barata porque a definicao vive
versionada no repositorio.

Uso:
  python src/genie/aplicar.py --catalogo grid_dev --schema-gold gold
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

TITULO = "Grid Intelligence - Copiloto de Operacoes"
ARQUIVO = Path(__file__).with_name("genie_space.json")


def cli(*args):
    return subprocess.run(["databricks", *args], check=False, capture_output=True,
                          text=True, encoding="utf-8", errors="replace")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--catalogo", required=True)
    p.add_argument("--schema-gold", default="gold")
    p.add_argument("--profile", default="grid_intelligence")
    p.add_argument("--warehouse-id", default="955067506c83b4e8")
    args = p.parse_args()

    payload = ARQUIVO.read_text(encoding="utf-8")
    payload = payload.replace("${catalogo}", args.catalogo).replace("${schema_gold}", args.schema_gold)
    json.loads(payload)  # valida antes de enviar

    spaces = json.loads(cli("genie", "list-spaces", "--profile", args.profile, "-o", "json").stdout)["spaces"]
    space_id = next((s["space_id"] for s in spaces if s.get("title") == TITULO), None)

    if space_id:
        r = cli("genie", "update-space", space_id,
                "--serialized-space", payload, "--title", TITULO,
                "--profile", args.profile, "-o", "json")
        acao = "atualizado"
    else:
        r = cli("genie", "create-space", args.warehouse_id, payload,
                "--title", TITULO,
                "--description", "Copiloto conversacional em portugues do Brasil sobre a camada gold da Grid Intelligence. Responde em linguagem de negocio; nao acessa bronze nem silver.",
                "--profile", args.profile, "-o", "json")
        acao = "criado"

    if r.returncode != 0:
        print(r.stderr, file=sys.stderr)
        sys.exit(r.returncode)

    resultado = json.loads(r.stdout)
    print(f"Genie space {acao}: {resultado.get('space_id') or space_id}")


if __name__ == "__main__":
    main()
