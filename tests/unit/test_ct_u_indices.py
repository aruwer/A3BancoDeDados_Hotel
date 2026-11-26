"""CT-U190 a CT-U192 · índices (critério 5 da rubrica)."""
from helpers import todos


def _indices(conn):
    return {n: d for n, d in todos(conn, """
        SELECT indexname, indexdef FROM pg_indexes
        WHERE schemaname = 'public' AND indexname NOT LIKE 'pk_%' AND indexname NOT LIKE 'uk_%'
          AND indexname NOT LIKE '%_key'""")}


def test_ct_u190_existem_os_tres_indices_da_aplicacao(conn):
    """When consulto pg_indexes ignorando índices de PK e UK
    Then existem idx_reserva_hospede, idx_consumo_reserva e idx_reserva_status_entrada (e nenhum a mais)"""
    assert sorted(_indices(conn)) == ["idx_consumo_reserva", "idx_reserva_hospede", "idx_reserva_status_entrada"]


def test_ct_u190_indices_de_fk_cobrem_a_coluna_certa(conn):
    """When leio a definição dos índices de FK
    Then idx_reserva_hospede indexa reserva(id_hospede) e idx_consumo_reserva indexa consumo_servico(id_reserva)"""
    idx = _indices(conn)
    assert "ON public.reserva USING btree (id_hospede)" in idx["idx_reserva_hospede"]
    assert "ON public.consumo_servico USING btree (id_reserva)" in idx["idx_consumo_reserva"]


def test_ct_u192_indice_composto_respeita_igualdade_e_depois_faixa(conn):
    """When leio idx_reserva_status_entrada
    Then as colunas estão na ordem (status_reserva, data_entrada_prevista): igualdade primeiro, faixa depois"""
    assert "(status_reserva, data_entrada_prevista)" in _indices(conn)["idx_reserva_status_entrada"]
