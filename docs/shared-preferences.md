# Chaves de `SharedPreferences`

Todas as chaves que a biblioteca grava em `SharedPreferences` começam com
`do_once_`. A aplicação e outras bibliotecas devem reservar esse prefixo para o
`flutter_execution`: o prefixo, sozinho, não comprova a origem de uma chave se
outro componente também o utilizar.

| Escopo | Formato da chave | Valor |
| --- | --- | --- |
| Permanente | `do_once_forever_<chave>` | `true` após conclusão; `false` após revogação |
| Diário | `do_once_daily_v2_<AAAA-MM-DD>_<chave>` | `true` após conclusão no dia local da chamada |
| Sessão | Nenhuma chave persistente | Mantido somente em memória |

`revokeKey` altera o marcador permanente da chave fornecida, quando ele existe,
e o estado em memória da sessão; não revoga marcadores diários. `dispose()`
aguarda as ações aceitas e limpa o estado da sessão em memória, mas **não apaga
preferências**, inclusive as da própria biblioteca.

## Mudança do prefixo anterior

Marcadores `A2S-Execution_*` e `A2S-Execution-daily-v2_*` são ignorados e não
são migrados, alterados ou apagados automaticamente. Ao atualizar, uma ação
permanente já concluída pode executar novamente; uma ação diária já concluída
também pode executar novamente no mesmo dia. Considere esse comportamento antes
de atualizar aplicações com efeitos externos. A mudança de prefixo não restaura
preferências que já tenham sido apagadas por versões anteriores.

Para uma eventual limpeza seletiva, não use `SharedPreferences.clear()`, que
remove preferências de todos os componentes. Uma operação de limpeza não faz
parte desta API; qualquer implementação futura deve limitar sua seleção às
chaves pertencentes à biblioteca, considerando que o prefixo é um namespace
reservado por convenção, não uma garantia de propriedade.
