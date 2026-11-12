# Chaves de `SharedPreferences`

Todas as chaves gravadas pela biblioteca começam com `do_once_`. A aplicação e
outras bibliotecas devem reservar esse prefixo para `do_once`.

| Escopo | Formato da chave | Valor |
| --- | --- | --- |
| Permanente | `do_once_forever_<chave>` | `true` após conclusão; `false` após revogação |
| Diário | `do_once_daily_v2_<AAAA-MM-DD>_<chave>` | `true` após conclusão; `false` após revogação |
| Sessão | Nenhuma chave persistente | Mantido em memória durante a vida do isolate |

`Do.revoke` altera apenas o escopo informado; no escopo diário, usa a data local
atual. Não apaga preferências da aplicação e não aguarda ações em andamento.
Uma ação ainda em execução pode registrar sua conclusão após a revogação.
