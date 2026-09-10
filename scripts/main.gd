extends Control

## Punch Challenge — a máquina de soco da Lazer & Sport.
##
## TELA EM PÉ, 1080 × 1920, LIDA EM BANDAS. Quem joga está a dois ou três
## metros do gabinete e olha para cima. A tela é dividida em faixas
## horizontais fixas (`BANDA_*`), e cada coisa desenhada mora dentro da
## sua: cabeçalho, alvo do soco, leitura (número e veredito),
## cartões e rodapé. Enquanto tudo respeitar a sua banda, nada se
## sobrepõe — que é a diferença entre um placar que se lê de longe e um
## amontoado de texto por cima de texto.
##
## O nó raiz desenha textos, placar e a Central Técnica; o cenário vivo
## fica nos filhos: `PunchBackground` (fundo), `LedFrame` (moldura de LEDs) e
## `AudioBank` (sons). O que voa — confete, faísca, estilhaço — mora em
## `fx.gd`.
##
## O CAMINHO DE QUEM JOGA:
##
##   ABERTURA → (START) → 3, 2, 1 → SENSOR ARMADO → IMPACTO → RESULTADO
##
## O soco só existe de um jeito: o MPU-6050 do alvo manda HIT pela
## serial (protocolo V2, ver docs/PROTOCOLO_SERIAL.md). Não há tecla
## nem simulação de bancada — só o sensor de verdade marca ponto.

const TELA := Vector2(1080.0, 1920.0)
const ArcadeStage = preload("res://scripts/presentation/arcade_stage.gd")

# ======================================================================
# AS BANDAS DA TELA
# ======================================================================
## Cabeçalho: marca do jogo e modo de operação.
const BANDA_TOPO := 150.0
## Alvo do soco: de onde saem ondas, faíscas e clarão.
const PALCO_TOPO := 162.0
const PALCO_BASE := 1032.0
## O MEDALHÃO: o visor da máquina. Uma máquina de fliperama tem UM
## painel de placar, e é ele que a pessoa olha em todo momento do jogo —
## na contagem, na carga, no impacto e no resultado. Por isso o medalhão
## não é "a tela do resultado": é o visor, e cada estado só troca o que
## está escrito dentro dele.
const MEDALHAO_CENTRO := Vector2(540.0, 1245.0)
const MEDALHAO_RAIO := 186.0
## Leitura: o veredito e o convite, embaixo do visor.
const LEITURA_TOPO := 1450.0
const LEITURA_BASE := 1600.0
## Cartões de recorde/partidas/créditos.
const CARTOES_Y := 1622.0
const CARTOES_ALTURA := 122.0
## Rodapé: assinatura da casa e, só na bancada, as teclas de teste.
const RODAPE_Y := 1876.0
## Margem lateral livre de moldura de LED.
const MARGEM := 60.0
## O ALVO NA TELA. É o centro do visor — o mesmo lugar em que o farol
## chama o soco e em que o número nasce logo depois.
const ALVO_DO_SOCO := Vector2(540.0, 930.0)
const LARGURA_UTIL := TELA.x - MARGEM * 2.0

## As cores que voam. Saem da paleta porque confete branco, que num
## fundo preto era o mais vistoso, é justamente o que some num fundo claro.
const CORES_FESTA := Paleta.FESTA

## Quantas marcas a máquina guarda.
const RANKING_TAMANHO := 20

# ======================================================================
# A CENTRAL TÉCNICA, DESCRITA UMA VEZ SÓ
# ======================================================================
## A CENTRAL TEM PÁGINAS.
##
## Ela cabia numa tela só enquanto tinha modo, faixas e sensor. Com o
## mapeamento dos botões do gabinete, a calibração, a câmera e a mesa de
## som, passou a caber empilhando coisa por cima de coisa — e uma tela de
## configuração com controle escondido atrás de outro é onde o técnico
## clica errado e some com a regulagem da casa.
##
## Quatro páginas, cada uma com um assunto: como a máquina opera, como
## ela mede o golpe, o que ela vê e ouve, e o que ela guardou.
const PAGINAS := ["OPERAÇÃO", "GOLPE", "CÂMERA E SOM", "DADOS"]

## Os retângulos dos botões NÃO são escritos à mão. Um par de − / + com o
## valor no meio é um "passo" (`_passo`), e é ele que decide onde ficam
## os dois botões e onde sobra espaço para o número. Foi um número
## escrito por cima de um botão que motivou isso: com a conta num lugar
## só, o texto não tem como invadir a área de clique.
const LADO_BOTAO := 64.0
## Passos: chave -> retângulo total (botões nas pontas, valor no meio).
## NENHUM RETÂNGULO PODE ENCOSTAR NO OUTRO **DENTRO DA MESMA PÁGINA**.
const PASSOS := {
	"vmin": Rect2(110, 404, 400, LADO_BOTAO),
	"vmax": Rect2(570, 404, 400, LADO_BOTAO),
	"curva": Rect2(110, 526, 400, 58),
	"zona": Rect2(570, 526, 400, 58),
	"porta": Rect2(110, 1010, 400, LADO_BOTAO),
	"raio": Rect2(110, 1124, 400, LADO_BOTAO),
	"amin": Rect2(570, 1124, 400, LADO_BOTAO),
	"vol_musica": Rect2(110, 1386, 400, LADO_BOTAO),
	"vol_efeitos": Rect2(570, 1386, 400, LADO_BOTAO),
}
## Botões simples: chave -> retângulo.
const BOTOES_SIMPLES := {
	"fechar": Rect2(920, 140, 68, 64),
	# --- página OPERAÇÃO
	"modo_livre": Rect2(110, 406, 400, 68),
	"modo_ficha": Rect2(570, 406, 400, 68),
	"mapear_start": Rect2(110, 620, 400, 68),
	"mapear_credito": Rect2(570, 620, 400, 68),
	# --- página GOLPE
	"eixo": Rect2(620, 1010, 280, LADO_BOTAO),
	"enviar_config": Rect2(110, 1300, 400, 60),
	"testar": Rect2(570, 1300, 400, 60),
	"calibrar": Rect2(300, 846, 480, 56),
	# --- página CÂMERA
	"camera": Rect2(110, 410, 260, 60),
	"trocar_camera": Rect2(390, 410, 260, 60),
	"foto_teste": Rect2(670, 410, 300, 60),
	"forcar_ponte": Rect2(110, 484, 400, 56),
	"sondar_camera": Rect2(570, 484, 400, 56),
	"diagnosticar": Rect2(110, 920, 400, 56),
	"instalar_camera": Rect2(570, 920, 400, 56),
	"testar_som": Rect2(300, 1498, 480, 60),
	# --- página DADOS
	"zerar": Rect2(110, 1358, 207, 60),
	"zerar_stats": Rect2(327, 1358, 207, 60),
	"zerar_ranking": Rect2(544, 1358, 207, 60),
	"reconectar": Rect2(761, 1358, 209, 60),
	"teto_efeitos": Rect2(680, 1234, 290, 56),
	# --- sempre visíveis
	"padroes": Rect2(110, 1782, 400, 68),
	"salvar": Rect2(570, 1782, 400, 68),
}
## Em que página cada controle vive. `-1` quer dizer "em todas".
##
## Sem esta tabela, um clique numa página acertaria o botão de outra —
## os retângulos continuam existindo mesmo quando não estão desenhados, e
## um botão invisível que responde é a pior espécie de defeito.
const PAGINA_DO_CONTROLE := {
	"fechar": -1, "padroes": -1, "salvar": -1,
	"modo_livre": 0, "modo_ficha": 0, "mapear_start": 0, "mapear_credito": 0,
	"vmin": 1, "vmax": 1, "curva": 1, "zona": 1,
	"porta": 1, "eixo": 1, "raio": 1, "amin": 1, "enviar_config": 1, "testar": 1,
	"calibrar": 1,
	"camera": 2, "trocar_camera": 2, "foto_teste": 2,
	"forcar_ponte": 2, "sondar_camera": 2, "instalar_camera": 2, "diagnosticar": 2,
	"vol_musica": 2, "vol_efeitos": 2, "testar_som": 2,
	"zerar": 3, "zerar_stats": 3, "zerar_ranking": 3, "reconectar": 3,
	"teto_efeitos": 3,
}
## As abas, no topo da caixa.
const ABA_LARGURA := 230.0
const ABA_RECT := Rect2(80, 250, 920, 62)

var state: GameDef.State = GameDef.State.IDLE
var central_aberta := false
var game_mode := "credit"
var credits := 0
var plays := 0
## AS CINCO MELHORES MARCAS, em ordem decrescente.
##
## Guardar cinco em vez de uma só não é enfeite: com um recorde único,
## quem não bate o recorde não ganha nada, e o recorde de uma máquina
## movimentada fica inalcançável em uma semana. Com uma lista, entrar em
## quinto ainda é entrar — e é essa pequena vitória que faz a pessoa
## pagar a segunda ficha.
var ranking: Array[Dictionary] = []
## Faixa de velocidade (m/s) que vira pontos no placar.
var hit_min_speed := ScoreCurve.DEFAULT_MIN_SPEED
var hit_max_speed := ScoreCurve.DEFAULT_MAX_SPEED
## O expoente é o botão de dificuldade da casa: quanto maior, mais tarde
## a nota sobe e mais raro fica o topo da escala. Os oito níveis têm
## faixas FIXAS, então é aqui — e só aqui — que se decide quanta gente
## chega a cada um deles.
var score_exponent := ScoreCurve.DEFAULT_EXPONENT
var score_dead_zone := ScoreCurve.DEFAULT_DEAD_ZONE
## Configuração enviada ao firmware (CONFIG,eixo,raio,vmin,amin).
var sensor_eixo := "X"
var sensor_raio := 0.45
var sensor_vmin := 0.8
var sensor_amin := 3.5
## Porta serial configurada; "" = automática (primeira disponível).
var porta_configurada := ""

var countdown_left := 3.0
var last_count := 3
var espera_left := GameDef.ESPERA_DO_SOCO
## Se a rodada em curso debitou uma ficha. É o que autoriza a devolução
## quando a espera acaba sem soco — e, sendo consumido na devolução,
## impede que a mesma ficha volte duas vezes.
var credito_gasto := false
## O GOLPE DA RODADA JÁ FOI. Um soco por rodada: o saco balança depois do
## impacto e o MPU-6050 vê esse balanço como um segundo evento.
var golpe_registrado := false
## Instante do último golpe ACEITO, para o tempo morto entre eventos.
##
## Começa em NUNCA, e não em zero. `Time.get_ticks_msec()` conta desde o
## start do processo: com zero, "faz quanto tempo desde o último golpe"
## dava menos que o tempo morto durante o primeiro segundo de máquina
## ligada, e o primeiro soco da manhã era recusado em silêncio.
const NUNCA_MS := -1000000
var ultimo_golpe_ms := NUNCA_MS
## O firmware avisou que o acelerômetro saturou. Fica registrado para a
## Central; um golpe saturado NÃO vira 9999 artificial, porque a máquina
## não sabe quanto ele valeu de verdade.
var saturacao_recente := ""

## OS DOIS BOTÕES DO GABINETE, mapeados e guardados.
##
## A placa Zero Delay se apresenta ao sistema como um controle USB
## genérico, e o índice de cada botão muda conforme a porta, o cabo e o
## modelo da placa. Um índice fixo no código funciona numa máquina e erra
## na seguinte — por isso o mapeamento é feito na Central, apertando o
## botão de verdade, e o que fica gravado é o que aquela máquina viu.
##
## `guid` identifica o controle; `index` é o botão; `nome` é o que o
## sistema chama aquele controle, para o técnico reconhecer a placa.
var botao_start := {"guid": "", "index": 6, "nome": ""}
var botao_credito := {"guid": "", "index": 4, "nome": ""}
## "" | "start" | "credito" — o que a Central está esperando capturar.
var mapeando := ""
## Contadores de teste: sobem a cada aperto reconhecido. São a prova de
## que o mapeamento pegou; sem eles o técnico aperta o botão e não sabe
## se o problema é a placa, o índice ou o jogo.
var contador_start := 0
var contador_credito := 0
## ANTIRREPIQUE. Botão de arcade é chave mecânica e treme ao fechar: um
## aperto vira dois ou três eventos em poucos milissegundos, e o segundo
## viraria um crédito a mais ou um START engolindo a rodada recém-criada.
const REPIQUE_MS := 250
var ultimo_start_ms := NUNCA_MS
var ultimo_credito_ms := NUNCA_MS
## Qual página da Central está aberta.
var central_pagina := 0
## Volume das duas mesas que o operador regula, em dB. Vão do silêncio
## prático (-40) a um pouco acima do nominal (+6): um salão barulhento
## precisa de mais, e uma loja de shopping precisa de bem menos.
var volume_musica := 0.0
var volume_efeitos := 0.0
## Quanto tempo faz que alguém apertou START sem saldo. Enquanto é curto,
## o lugar do crédito pisca na abertura: apontar para onde a ficha entra
## resolve mais do que qualquer frase.
var aviso_de_credito := -1.0
## Marcado quando `_carregar` converteu marcas da escala antiga. `_ready`
## grava logo em seguida, e é isso que torna a conversão de uma vez só.
var _converteu_esquema := false
## A ESTRELA DE PANCADA: quanto tempo desde o golpe, com que força e de
## qual nível. Negativo quer dizer que não há pancada no ar.
var pancada_tempo := -1.0
var pancada_forca := 0.0
var pancada_nivel: Dictionary = {}
## HIT-STOP: o congelamento curto que dá peso ao golpe. Enquanto ele
## corre, o relógio do jogo PARA — animação, contagem e máquina de
## estados — e só a tela continua sendo desenhada. É o que faz um
## nocaute parecer que acertou alguma coisa sólida.
var hitstop_left := 0.0
## ZOOM DE IMPACTO: a tela inteira cresce um pouco e volta. Fica no
## desenho, não na câmera, porque não há câmera — o jogo é um `_draw`.
var zoom_impacto := 1.0
var zoom_alvo := 1.0
## A CORTINA ENTRE UMA TELA E OUTRA.
##
## Antes as telas trocavam no meio de um quadro: a foto virava o alvo, o
## alvo virava o placar, tudo de um pixel para o outro. Num monitor de
## fliperama isso não lê como "mudou de tela", lê como falha de imagem.
##
## Agora uma faixa diagonal atravessa a tela a cada troca, na cor da
## marca, com o alvo do jogo montado nela. Meio segundo, o tempo de a
## pessoa entender que a máquina avançou.
var transicao := -1.0
const TRANSICAO_DURACAO := 0.38
var result_score := 0
var result_speed := 0.0
var result_simulado := false
## Posição conquistada no ranking (1 a 5), ou 0 se o golpe não entrou.
var posicao_no_ranking := 0
var displayed_score := 0.0
var animation_time := 0.0
var state_time := 0.0
var result_time := 0.0
var verdict_time := -1.0
var proximo_tique := 0
var proximo_fogo := 0.0
var tremor := 0.0
var clarao := 0.0
var notice := ""
var notice_left := 0.0
var confirm_action := ""
var confirm_until := 0.0

## Serial.
var link: SerialLink
var serial_status := "INICIANDO"
var porta_atual := ""
var ultimo_sinal_ms := -1
var proxima_tentativa := 0.0
var proximo_ping := 0.0
## Última telemetria, exibida na Central Técnica.
var telemetria := ""
var portas_visiveis: PackedStringArray = []
## Quantos apertos de botão chegaram PELA SERIAL nesta sessão. Separados
## dos do Zero Delay de propósito: são dois caminhos diferentes, e saber
## qual dos dois está mudo é metade do conserto.
## O MPU-6050 se apresentou nesta sessão? Separado de "a placa
## respondeu": desde que o firmware deixou de travar sem sensor, as duas
## coisas passaram a ser independentes.
## O estado CRU dos dois pinos, como a placa os lê agora. Não é "o jogo
## aceitou o aperto": é o fio.
var pino_start := false
var pino_credito := false
var sensor_presente := false
var serial_start := 0
var serial_credito := 0
## Quando a porta atual foi CONFIRMADA aberta. Serve para desistir dela.
var _porta_aberta_em := 0.0
## Quando a abertura foi PEDIDA. Não é a mesma coisa, e a diferença é o
## defeito: pela ponte por processo o pedido atravessa um cano, um
## PowerShell e um driver antes de a porta abrir de verdade. Contar a
## paciência a partir do pedido é descontar dela o tempo do encanamento —
## e num PC lento o encanamento come a paciência inteira antes de a placa
## ter chance de falar. Ver `ESPERA_DA_CONFIRMACAO`.
var _porta_pedida_em := 0.0
var _porta_confirmada := false
## A fila de portas desta volta, e onde a volta está.
var _fila_de_portas: PackedStringArray = []
## Quantas voltas completas já foram dadas na fila. Vai para a tela: uma
## busca que mostra o número da volta é uma busca que se vê acontecendo,
## e não uma que "nunca termina".
var _varreduras := 0
## Quantas vezes a porta FIXADA na Central falhou seguidas.
var _falhas_da_porta_fixa := 0
## Quando o caminho atual até a placa entrou em uso, e quantas vezes o
## jogo já trocou de caminho nesta sessão.
var _caminho_desde := 0.0
var _trocas_de_caminho := 0
var _proxima_escolha_de_caminho := 0.0
## A VARREDURA CEGA, UMA VEZ LIBERADA, NÃO VOLTA A SER TRANCADA.
##
## Ela entra depois da primeira volta sem sucesso — e a partir daí vale
## para o resto da sessão, inclusive depois de uma troca de caminho.
## Amarrá-la a `_varreduras`, que zera a cada troca de caminho, faria a
## troca de caminho DESLIGAR a varredura cega justamente na máquina onde
## as duas são necessárias.
var _cega_liberada := false
## ESTE CAMINHO JÁ ENTREGOU UMA LINHA DE VERDADE NESTA MÁQUINA?
##
## Se já, ele está provado e não se troca mais — nem depois de um silêncio
## longo. Um caminho que funcionou uma vez volta a funcionar quando o
## cabo voltar; trocá-lo por causa de uma queda seria jogar fora a única
## coisa que se sabe sobre esta máquina.
var _caminho_provado := false
## A PLACA JÁ FALOU NESTA PORTA? Substitui a pergunta antiga, que era
## `"CONECTADO" in serial_status` — e além de frágil ela estava errada:
## "DESCONECTADO" contém "CONECTADO", então a frase que diz que a placa
## caiu respondia que a placa estava lá.
var placa_respondeu := false

## Câmera e dados locais do proprietário. Nenhum deles depende da rede.
var camera_service: CameraService
var camera_enabled := true
## O ÍNDICE E O BACK-END QUE JÁ FUNCIONARAM NESTA MÁQUINA.
##
## Descobrir a câmera é a parte cara: no Windows, varrer dez índices em
## três back-ends leva a melhor parte de um minuto, e é isso que a
## máquina fazia toda vez que ligava. Guardado, o gabinete abre a webcam
## na primeira tentativa — e a foto da primeira partida da noite sai
## igual à da centésima.
var camera_index := 0
var camera_backend := ""
## O interpretador que o diagnóstico provou ter OpenCV, guardado entre
## sessões. Sem ele, toda vez que a máquina liga a ponte recomeça a
## adivinhar qual Python usar.
## O teto de efeitos escolhido na Central, guardado entre sessões.
var teto_efeitos := "AUTO"
var camera_python := ""
var camera_python_args := ""
var camera_mirrored := true
## Pula o CameraServer e vai direto à ponte Python. Guardado em disco:
## numa máquina em que o caminho nativo nunca funciona, ligar isso uma
## vez tem de valer para sempre.
## O CAMINHO NATIVO VEM PRIMEIRO — PORQUE ELE NÃO PRECISA DE PYTHON.
##
## Esta chave já esteve nas duas posições, e a razão de voltar atrás é a
## que mais importa numa máquina de salão: A PONTE EXIGE PYTHON E OPENCV
## INSTALADOS. Num PC recém-formatado, ou no notebook que se leva para uma
## festa, isso não existe — e uma máquina que só fotografa em computador
## preparado não serve para um negócio que roda em computador qualquer.
##
## Antes eu tinha posto a ponte na frente no Windows porque o caminho
## nativo enumerava a câmera e entregava quadro PRETO. Só que a essa
## altura o preto passava despercebido: hoje existe a checagem de
## contraste, e um feed que não entrega imagem de verdade é reprovado em
## dois segundos e meio e cai para a ponte sozinho.
##
## Então a ordem certa é: tenta o nativo, que não precisa de nada
## instalado; se ele não provar que funciona, a ponte entra como reserva.
## O pior caso são dois segundos e meio na abertura; o melhor caso é uma
## máquina que fotografa num PC sem nada.
var camera_forcar_ponte := false
var camera_ponte_escolhida := false
## Quem roda os comandos de diagnóstico e publica a resposta na tela.
var medico: CameraDoctor
var statistics: Dictionary = {}
var result_photo_path := ""
var pose_finished := false
## A CONTAGEM SEGURA ENQUANTO A CÂMERA NÃO ACENDE.
##
## E segura com HORA MARCADA. Uma máquina sem webcam, com o cabo solto ou
## com o Python faltando não pode ficar sem jogar: quem pôs a ficha tem
## direito à partida, com foto ou sem. Passados estes segundos a rodada
## começa assim mesmo, e a tela diz por quê.
const ESPERA_MAXIMA_DA_CAMERA := 6.0
var aguardando_camera := false
var espera_da_camera := 0.0
## A FOTO É DA POSE FINAL, NÃO DE QUALQUER MOMENTO DA CONTAGEM.
##
## Ver o comentário grande em `_processar_contagem`. O obturador só abre
## dentro desta janela final, em segundos antes de a contagem zerar.
const JANELA_TARDIA_OBTURADOR_SEGUNDOS := 0.5
var _obturador_tardio_aberto := false
var photo_retained := false
var ranking_announced := false
var intro_active := true
var intro_time := 0.0
## O QUANTO A ABERTURA JÁ CHEGOU, de 0 a 1.
##
## A entrada termina pousando o emblema e o letreiro exatamente onde a
## abertura os desenha, e por isso esses dois não podem esmaecer de novo.
## Mas o resto da abertura — o cabeçalho, o convite, os créditos — não
## existe na entrada e apareceria de um quadro para o outro. Este número
## faz só essa mobília entrar suave, sem tocar no que já estava na tela.
var abertura_chegada := 1.0
## Quanto tempo a tela de espera está no ar sem repetir a apresentação.
var atracao_relogio := 0.0
var _photo_cache: Dictionary = {}
## O CACHE DE FOTOS NÃO PODE SER DECODIFICADO NA LINHA DO JOGO.
##
## `_photo_texture` lê o arquivo e decodifica o JPEG na hora — barato UMA
## vez, mas o Top 20 mostra até cinco fotos por quadro durante a entrada
## animada da tabela, e toda foto ainda não vista custa isso de novo. É
## esse o travamento "ao apresentar o ranking": não é um travamento só,
## é um por foto nova que aparece rolando.
##
## A decodificação agora roda no pool de linhas do Godot — o mesmo
## esquema já usado para o quadro da câmera em `camera_service.gd` — e
## a linha do jogo só cria a textura (rápido) quando a imagem já está
## pronta. Chamado assim que o placar entra no ranking, isso dá vários
## segundos de folga antes de a tabela precisar de fato mostrar a foto.
var _mutex_fotos := Mutex.new()
var _fotos_decodificadas: Dictionary = {}

var fx := PunchFX.new()
## O VIGIA DO RITMO. Mede o quadro e, quando a máquina não dá conta,
## manda os efeitos gastarem menos — sozinho, sem ninguém configurar.
var desempenho := Desempenho.new()
## Deslocamento do tremor no quadro atual. Fica guardado porque o texto
## curvo troca a transformação do canvas e precisa devolvê-la exatamente
## como estava — senão o tremor some do resto da tela a partir dali.
var _deslocamento := Vector2.ZERO
## AS DUAS LETRAS DA MÁQUINA — e o motivo de serem duas.
##
## A Bungee é uma fonte de CARTAZ: letra larga, caixa alta, feita para
## ser lida atravessando a rua. É a letra certa para PUNCH CHALLENGE, para
## a pontuação e para o nome da faixa do golpe, e é ela que combina com o
## logotipo da casa.
##
## O erro era usar a mesma Bungee nos rótulos de 22 px. Nesse corpo ela
## fecha os contra-formas — o buraco do "a", do "e", do "o" —, os acentos
## grudam na letra e a linha vira uma barra cinza: exatamente o "feio e
## embaçado" que se vê na tela. Nenhum ajuste de renderização conserta
## isso, porque não é falta de nitidez, é a fonte errada para o tamanho.
##
## A Saira Condensed entra só onde se LÊ: rótulos, instruções, Central
## Técnica, rodapés. É estreita (cabe "PRESSIONE START" sem encolher),
## tem acentuação completa do português e mantém o buraco da letra aberto
## a 20 px. O cartaz continua Bungee, então a identidade não muda — muda
## só o lugar em que a letra tinha de trabalhar e não conseguia.
var fonte: Font        ## Bungee: o cartaz.
var fonte_texto: Font  ## Saira Condensed: a leitura.
var logo: Texture2D = null

@onready var letreiro_do_nome: Letreiro = $Letreiro
@onready var fundo: PunchBackground = $Fundo
@onready var moldura: LedFrame = $Moldura
@onready var sons: AudioBank = $Audio

func _ready() -> void:
	fonte = ThemeDB.fallback_font
	if ResourceLoader.exists("res://assets/fonts/Bungee-Regular.ttf"):
		fonte = load("res://assets/fonts/Bungee-Regular.ttf")
	# A letra de leitura cai para a de cartaz se o arquivo faltar: uma
	# tela com a fonte errada ainda é uma tela; uma tela sem fonte não é.
	fonte_texto = fonte
	if ResourceLoader.exists("res://assets/fonts/SairaCondensed-ExtraBold.ttf"):
		fonte_texto = load("res://assets/fonts/SairaCondensed-ExtraBold.ttf")
	letreiro_do_nome.fonte = fonte
	# AQUECE O SOMBREADOR DO NOME ANTES DE A ABERTURA PRECISAR DELE.
	#
	# `Letreiro` é o ÚNICO nó do jogo com material próprio (o brilho que
	# corre dentro das letras, em `shaders/brilho_letras.gdshader`) — e
	# ele só desenha pela primeira vez quando a entrada acaba e a tela de
	# espera aparece (`_nome_do_jogo`, chamada só fora da entrada). Um
	# programa de sombreador NUNCA usado antes é compilado pelo driver no
	# primeiro desenho que o usa — não antes —, e num driver fraco ou
	# embarcado (a mesma categoria de placa por trás do ajuste de
	# `driver/threads/thread_model` em project.godot) isso é uma pausa
	# real, sentida bem naquele quadro. É exatamente onde o travamento
	# "o jogo vai se posicionar e o nome" acontecia: não é o
	# posicionamento, é a primeira vez que o brilho do nome é desenhado.
	#
	# Mostrando o nome uma vez aqui, com alfa zero, o desenho acontece de
	# verdade — e o sombreador compila — nos primeiros quadros do jogo,
	# antes mesmo de a entrada começar a tocar, quando ninguém está
	# olhando para o lugar certo ainda. `_nome_do_jogo` assume o nó de
	# volta (mostra e esconde) assim que a entrada termina, sem saber
	# que ele já foi usado uma vez.
	letreiro_do_nome.mostrar(
		[
			{"texto": "PUNCH", "x": 540.0, "y": 910.0, "tamanho": 144, "cor": Color(Color.WHITE, 0.0)},
			{"texto": "CHALLENGE", "x": 540.0, "y": 1010.0, "tamanho": 80, "cor": Color(Paleta.AMBAR, 0.0)},
		],
		190.0, 700.0
	)
	fx.vigia = desempenho
	if ResourceLoader.exists("res://assets/logo_lazersport.png"):
		logo = load("res://assets/logo_lazersport.png")
	_carregar()
	# AQUECE O CACHE DE FOTOS ANTES DE PRECISAR DELE. A primeira vez que
	# o Top 20 aparece depois de a máquina ligar era exatamente a pior
	# hora para decodificar vinte JPEGs na linha do jogo -- é quando
	# menos se espera um travamento, logo na primeira rodada do dia.
	_prewarm_fotos_do_ranking()
	camera_service = CameraService.new()
	camera_service.enabled = camera_enabled
	camera_service.selected_index = camera_index
	camera_service.backend_preferido = camera_backend
	if not camera_python.is_empty():
		var guardados := PackedStringArray()
		for a in camera_python_args.split(",", false):
			guardados.append(str(a))
		camera_service.adotar_python(camera_python, guardados)
	camera_service.mirrored = camera_mirrored
	camera_service.forcar_ponte = camera_forcar_ponte
	add_child(camera_service)
	medico = CameraDoctor.new()
	medico.terminou.connect(_fim_do_exame)
	add_child(medico)
	sons.set_volumes(volume_musica, volume_efeitos)
	_aplicar_faixas()
	if _converteu_esquema:
		_converteu_esquema = false
		_salvar()
		_show_notice("MARCAS CONVERTIDAS PARA A ESCALA 0000 – 9999")
	_iniciar_serial()
	_entrar_em_abertura()
	# A música entra baixa por baixo da entrada e sobe na virada para a
	# abertura: a trilha crescendo é o que faz a entrada terminar em vez
	# de simplesmente parar. As deixas da entrada tocam por cima.
	sons.music(-30.0)
	set_process(true)

func _exit_tree() -> void:
	if link != null:
		link.close_port()
		# A ponte por processo tem um ajudante do lado de fora: fechar a
		# porta nao basta, o processo precisa ir junto. Sem isto o jogo
		# fecha e deixa um PowerShell segurando a COM -- e a proxima
		# partida nao consegue abrir a porta da propria maquina.
		link.encerrar()
	_photo_cache.clear()

## Um lugar só onde os parâmetros da curva são saneados.
##
## Os oito níveis têm faixas fixas, então não há mais limite ajustável
## para arrumar: o que precisa de saneamento é a curva, e ela é a mesma
## que a Central desenha, que o placar usa e que o firmware recebe. Uma
## passagem só por `ScoreCurve.sanitize` mantém as três concordando.
func _aplicar_faixas() -> void:
	var cfg := ScoreCurve.sanitize(hit_min_speed, hit_max_speed, score_exponent, score_dead_zone)
	hit_min_speed = cfg["min_speed"]
	hit_max_speed = cfg["max_speed"]
	score_exponent = cfg["exponent"]
	score_dead_zone = cfg["dead_zone"]

## A melhor marca da casa. Sai do topo do ranking, e não de uma variável
## paralela — duas fontes para o mesmo número é como elas divergem.
func _melhor() -> int:
	return RankingStore.best(ranking)

## Insere uma pontuação e devolve a posição conquistada (1 a 5), ou 0 se
## ela não foi boa o bastante para entrar na lista.
func _entrar_no_ranking(pontos: int, foto := "", origem := "SENSOR") -> int:
	var inserted := RankingStore.insert(ranking, pontos, foto, origem)
	ranking.assign(inserted["entries"])
	for path in inserted["dropped_photos"]:
		RankingStore.delete_photo(path)
	return int(inserted["position"])

## ONDE O SOCO ATERRISSA NA TELA.
##
## Antes era o saco de pancadas desenhado que dizia o ponto. Sem ele, o
## alvo é o próprio visor: é dele que saem as ondas, as faíscas e o
## clarão, e é para ele que a tela de espera chama o punho. Um lugar só,
## para que efeito e imagem nunca discordem.
func _alvo() -> Vector2:
	return ALVO_DO_SOCO

# ======================================================================
# CICLO
# ======================================================================
func _process(delta: float) -> void:
	# O HIT-STOP CONGELA O JOGO, E SÓ ELE ANDA. Nem `animation_time` nem
	# a máquina de estados avançam: se avançassem, o congelamento seria
	# só um quadro repetido enquanto o resto seguia, e a pessoa sentiria
	# um engasgo em vez de um golpe pesado.
	if hitstop_left > 0.0:
		hitstop_left = maxf(0.0, hitstop_left - delta)
		queue_redraw()
		return
	_colher_fotos_decodificadas()
	desempenho.medir(delta)
	# UM QUADRO ENGASGADO NÃO PODE VIRAR UM PULO NO JOGO — MAS O FREIO NÃO
	# PODE VIRAR CÂMERA LENTA.
	#
	# `desempenho.medir` já viu o quadro de verdade, com o tempo real que
	# ele levou — é dele que sai a média de FPS e a decisão de cortar
	# efeito. Este teto serve só para um caso raro: um engasgo isolado e
	# GRANDE (a primeira vez que uma fonte nova é rasterizada, um soluço
	# do sistema operacional) que faria o quadro seguinte herdar um delta
	# gigante e o jogo INTEIRO pular esse tanto de uma vez — a contagem
	# saltando números, a brasa teletransportando em vez de voar.
	#
	# O teto tinha ficado em 1/30 s (a máquina "não pode ficar mais lenta
	# que 30 fps"), e isso é OUTRA COISA: numa tela mais pesada de
	# desenhar — a abertura, com o cenário inteiro e a luva voando, ou o
	# instante do impacto, com a explosão de partículas — a máquina PODE
	# rodar abaixo de 30 fps por um bom tempo, não só num quadro isolado.
	# Com o teto em 1/30 s, cada um DESSES quadros também tinha o tempo
	# cortado, e um jogo que anda com menos tempo do que o relógio real
	# passou fica em câmera lenta — foi exatamente essa a queixa: a
	# contagem do impacto e o posicionamento da abertura ficaram lentos.
	# Um freio para casos raros e extremos não pode disparar toda vez que
	# a tela fica mais pesada por alguns segundos.
	#
	# O teto certo é bem mais alto: só entra numa queda catastrófica
	# (abaixo de 10 fps, meio segundo por quadro pra cima), que nunca
	# acontece pelo simples peso normal de uma tela cheia de efeito — só
	# por um soluço de verdade. Abaixo disso o passo do jogo é o próprio
	# tempo do quadro, e a máquina anda no seu próprio ritmo real, só mais
	# aos trancos quando o PC está fraco — o que é honesto, e não lento.
	var passo := minf(delta, 0.1)
	# O cenário é a camada mais cara do jogo; quando a máquina aperta, ela
	# encolhe junto com os efeitos.
	ArcadeStage.enfeite = desempenho.qualidade
	# A MOLDURA DE LED NÃO ENCOLHIA NUNCA. Cem e tantas lâmpadas, três
	# desenhos cada, em toda tela do jogo, do início ao fim — o único
	# enfeite que ficava de fora do vigia de desempenho.
	moldura.qualidade = desempenho.qualidade
	_socorro_da_camera(passo)
	_laco_de_atracao(passo)
	zoom_impacto = lerpf(zoom_impacto, zoom_alvo, clampf(passo * 7.0, 0.0, 1.0))
	if absf(zoom_impacto - 1.0) < 0.002 and is_equal_approx(zoom_alvo, 1.0):
		zoom_impacto = 1.0
	animation_time += passo
	state_time += passo
	_poll_serial(passo)
	fx.atualizar(passo)
	tremor = maxf(0.0, tremor - passo * 26.0)
	clarao = maxf(0.0, clarao - passo * 2.6)
	if transicao >= 0.0:
		transicao += passo
		if transicao > TRANSICAO_DURACAO:
			transicao = -1.0
	if pancada_tempo >= 0.0:
		pancada_tempo += passo
		# O zoom volta ao normal assim que o estrelão passa da metade.
		if pancada_tempo > ImpactDirector.PANCADA_DURACAO * 0.5:
			zoom_alvo = 1.0
		if pancada_tempo > ImpactDirector.PANCADA_DURACAO:
			pancada_tempo = -1.0

	if notice_left > 0.0:
		notice_left -= passo
	else:
		notice = ""
	if not confirm_action.is_empty() and animation_time > confirm_until:
		confirm_action = ""

	if central_aberta:
		_processar_calibracao(passo)
	if not central_aberta:
		match state:
			GameDef.State.IDLE:
				_processar_abertura(passo)
			GameDef.State.COUNTDOWN:
				_processar_contagem(passo)
			GameDef.State.ARMED:
				_processar_armado(passo)
			GameDef.State.MEASURING:
				if state_time >= GameDef.IMPACTO_DURACAO:
					_entrar_em_resultado()
			GameDef.State.RESULT:
				_processar_resultado(passo)
	queue_redraw()

func _processar_abertura(delta: float) -> void:
	if intro_active:
		var antes := intro_time
		intro_time += delta
		# As deixas sonoras vêm da mesma tabela que desenha a entrada.
		# Ler o intervalo (antes, agora] em vez de "passou de" é o que
		# impede uma deixa de sumir num quadro longo ou tocar duas vezes.
		for marca in ArcadeStage.intro_cues(antes, intro_time):
			sons.play(marca["cue"], marca["db"])
		# O soco da entrada sacode a máquina e cospe faíscas de verdade,
		# com o mesmo sistema do soco do jogador: uma entrada que promete
		# um impacto tem de entregar o impacto.
		if antes < ArcadeStage.T_SOCO and intro_time >= ArcadeStage.T_SOCO:
			tremor = 34.0
			clarao = 0.60
			fx.faiscas(ArcadeStage.SOCO, 26, Paleta.AMBAR, 1250.0)
			fx.onda(ArcadeStage.SOCO, 60.0, 620.0, Paleta.CREME, 12.0, 0.55)
			fx.poeira(ArcadeStage.SOCO + Vector2(0.0, 180.0), 14, Color(Paleta.AMBAR, 0.35), 380.0)
		if antes < ArcadeStage.T_MORPH and intro_time >= ArcadeStage.T_MORPH:
			sons.music(-16.0)
		if intro_time >= ArcadeStage.INTRO_SECONDS:
			intro_active = false
			# A abertura ENTRA JÁ NO AR, e não esmaecendo do zero. A
			# entrada acaba de pousar o emblema e o letreiro exatamente
			# onde a abertura os desenha; se ela ainda por cima começasse
			# com o seu próprio esmaecer, o quadro seguinte à entrada
			# seria um piscar — a única emenda visível do filme.
			state_time = 0.7
			abertura_chegada = 0.0
		return
	abertura_chegada = minf(1.0, abertura_chegada + delta * 2.2)
	if aviso_de_credito >= 0.0:
		aviso_de_credito += delta
		if aviso_de_credito > 2.6:
			aviso_de_credito = -1.0
	if randf() < delta * 4.0:
		fx.poeira(
			Vector2(randf_range(120.0, 960.0), TELA.y + 40.0),
			1, Color(Paleta.AMBAR, 0.30), 120.0
		)

func _processar_contagem(delta: float) -> void:
	if aguardando_camera:
		espera_da_camera += delta
		var pronta := camera_service != null and camera_service.pronta()
		# UMA CÂMERA QUE JÁ DESISTIU NÃO MERECE SER ESPERADA DE NOVO.
		#
		# Sem isto, uma máquina sem webcam nenhuma — ou com a ponte sem
		# Python, já desistida — pagava os SEIS SEGUNDOS inteiros de
		# `ESPERA_MAXIMA_DA_CAMERA` EM TODA RODADA, para sempre: a
		# contagem "FAÇA SUA POSE" ficava parada esperando uma imagem
		# que já se sabia, desde o fim da última tentativa, que não ia
		# chegar. Isso é exatamente "a câmera trava" e "se ela não for
		# detectada nem deve passar" — uma câmera desligada ou que já
		# esgotou as tentativas de religar (`Estado.PARADA`) não tem
		# mais nada a esperar; a rodada segue na hora.
		var desistiu := camera_service == null or camera_service.estado in [
			CameraService.Estado.PARADA, CameraService.Estado.DESLIGADA,
		]
		if not pronta and not desistiu and espera_da_camera < ESPERA_MAXIMA_DA_CAMERA:
			# A contagem NÃO anda: o relógio da pose só começa quando há
			# imagem para fotografar.
			return
		aguardando_camera = false
		if not pronta:
			_show_notice(
				camera_service.estado_curto() if camera_service != null else "SEM CÂMERA"
			)
	countdown_left -= delta
	# O OBTURADOR ABRE NA RETA FINAL, NÃO NA CONTAGEM INTEIRA.
	#
	# Antes `abrir_obturador()` era chamado lá no INÍCIO da contagem (nos
	# três segundos inteiros de "3-2-1"), com uma janela de 3,2 s — e o
	# obturador guarda o quadro de MAIOR CONTRASTE visto na janela toda,
	# não o mais recente. Isso significa que uma foto tirada no instante
	# em que a pessoa ainda está se ajeitando na frente da câmera — mal
	# chegou, luz de fundo mudando — podia vencer a pose final só por ter
	# mais contraste, mesmo a pessoa tendo se aprumado direito no segundo
	# seguinte. É exatamente "não capta se mudou depois do segundo 2".
	#
	# A pose que importa é a de QUANDO A CONTAGEM ACABA, e só ela. Abrindo
	# o obturador só na JANELA_TARDIA_OBTURADOR_SEGUNDOS final — meio
	# segundo antes de zerar —, o "melhor quadro" só pode vir de dentro
	# desse meio segundo: o suficiente para não perder a foto por um
	# único quadro escuro bem na hora, pouco o bastante para nunca mais
	# escolher uma pose de segundos atrás.
	if not pose_finished and not _obturador_tardio_aberto and camera_service != null \
			and countdown_left <= JANELA_TARDIA_OBTURADOR_SEGUNDOS:
		_obturador_tardio_aberto = true
		camera_service.abrir_obturador(int(JANELA_TARDIA_OBTURADOR_SEGUNDOS * 1000.0) + 250)
	if not pose_finished and countdown_left <= 0.0:
		pose_finished = true
		result_photo_path = camera_service.capture_photo() if camera_service != null else ""
		if not result_photo_path.is_empty() and camera_service.ultima_foto != null:
			# A textura sai da imagem que a câmera acabou de entregar, e
			# não do arquivo recém-gravado: ler o disco de volta no mesmo
			# quadro é o que fazia a imagem sumir e voltar no obturador.
			_photo_cache[result_photo_path] = ImageTexture.create_from_image(
				camera_service.ultima_foto
			)
		clarao = 0.65
		sons.play("shutter", -5.0)
		return
	var atual := maxi(0, int(ceil(countdown_left)))
	if atual > 0 and atual < last_count:
		last_count = atual
		sons.play("count")
		sons.duck(8.0, 0.5)
	if countdown_left <= -1.2:
		state = GameDef.State.ARMED
		_iniciar_transicao()
		state_time = 0.0
		espera_left = GameDef.ESPERA_DO_SOCO
		# A rodada nova começa sem golpe e sem saturação pendente.
		golpe_registrado = false
		saturacao_recente = ""
		sons.play("armado", -6.0)
		sons.play("go")
		sons.music(-19.0)
		moldura.set_estado(LedFrame.ARMADA)

func _processar_armado(delta: float) -> void:
	espera_left -= delta
	if espera_left <= 0.0:
		# A ESPERA ACABOU SEM SOCO — E A FICHA VOLTA.
		#
		# Antes a rodada simplesmente morria, com o crédito já debitado:
		# quem hesitou oito segundos pagou e não jogou, e é isso que
		# fazia o saldo evaporar sozinho. O limite continua existindo,
		# senão a máquina passa a tarde armada se a pessoa foi embora,
		# mas agora ele devolve em vez de cobrar.
		sons.play("error", -4.0)
		_devolver_credito()
		_entrar_em_abertura()

func _entrar_em_resultado() -> void:
	sons.start_score_loop()
	state = GameDef.State.RESULT
	state_time = 0.0
	result_time = 0.0
	displayed_score = 0.0
	proximo_tique = 0
	proximo_fogo = 0.0
	verdict_time = -1.0

func _processar_resultado(delta: float) -> void:
	result_time += delta
	var avanco := clampf(result_time / GameDef.CONTAGEM_DURACAO, 0.0, 1.0)
	# O número dispara e vai freando — o suspense que um placar de
	# arcade precisa ter. O veredito só entra quando a contagem termina.
	displayed_score = float(result_score) * ease(avanco, 0.42)

	sons.score_progress(avanco)
	_mandar_fitas(displayed_score / float(GameDef.SCORE_MAX))

	if verdict_time < 0.0 and avanco >= 1.0:
		_disparar_veredito()
	elif verdict_time >= 0.0:
		verdict_time += delta
		_manter_festa(delta)
		if verdict_time >= 2.5 and not ranking_announced:
			ranking_announced = true
			sons.play("ranking", -5.0)
			sons.music(-24.0)
		_marcar_atos_do_ranking()

	if result_time > GameDef.RESULTADO_TIMEOUT:
		_entrar_em_abertura()

## AS DEIXAS DOS QUATRO ATOS DA ENTRADA NO RANKING.
##
## Som e confete pendurados no mesmo relógio que o desenho, e cada um
## disparado UMA VEZ. É o que faz a batida da linha e o estouro do
## confete caírem no mesmo quadro do movimento que os justifica — e não
## meio segundo antes, que é quando a festa parece solta da tela.
var _ato_assentou := false
var _ato_festejou := false

func _marcar_atos_do_ranking() -> void:
	if posicao_no_ranking <= 0:
		return
	var t := _tempo_do_ranking()
	# A LINHA BATE NO LUGAR: som seco e um tranco curto na tela.
	if not _ato_assentou and t >= ATO_ANUNCIO + ATO_TABELA:
		_ato_assentou = true
		sons.play("hit", -6.0)
		tremor = maxf(tremor, 9.0)
	# E SÓ ENTÃO O CONFETE. Durante o movimento ele vira sujeira por cima
	# da informação; depois dele, vira festa.
	if not _ato_festejou and t >= ATO_ANUNCIO + ATO_TABELA + ATO_ASSENTA:
		_ato_festejou = true
		sons.play("record" if posicao_no_ranking == 1 else "win", -3.0)
		# DE FORA DA TELA, POR CIMA. Confete que nasce dentro da tabela
		# estoura em cima da informação e lê como sujeira; nascendo acima
		# da borda, ele DESCE sobre a tela e vira chuva de papel picado,
		# que é o que uma premiação tem.
		fx.confete(Vector2(200.0, -60.0), 40, CORES_FESTA, 620.0)
		fx.confete(Vector2(540.0, -90.0), 40, CORES_FESTA, 620.0)
		fx.confete(Vector2(880.0, -60.0), 40, CORES_FESTA, 620.0)

func _manter_festa(_delta: float) -> void:
	## A COMEMORAÇÃO QUE CONTINUA é do nível, e o intervalo entre os
	## estouros também. Um impacto leve tem intervalo zero e não comemora
	## nada: dizer "mandou bem" a quem não mandou é o jeito mais rápido
	## de a máquina perder a credibilidade.
	var nivel := ScoreTier.de(result_score)
	var intervalo := float(nivel["festa_intervalo"])
	# A FESTA DURA O VEREDITO INTEIRO, e não cinco segundos.
	#
	# Ela parava em 5 s, bem no meio da revelação do ranking — e a tela
	# mais importante da partida acontecia no silêncio visual que sobrava.
	# Agora acompanha o veredito até o fim, e os fogos entram no intervalo
	# do nível, que é mais espaçado do que era.
	if intervalo <= 0.0 or verdict_time >= 9.0 or verdict_time < proximo_fogo:
		return
	proximo_fogo = verdict_time + intervalo
	ImpactDirector.festa(fx, _alvo(), nivel, CORES_FESTA)
	# CADA FOGO TEM O SEU ESTOURO. Festa muda no som antes de mudar na
	# imagem: fogo mudo lê como enfeite de tela, não como comemoração.
	sons.play("subgrave", -14.0)

# ======================================================================
# ENTRADA DE COMANDOS
# ======================================================================
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F9:
			_toggle_central()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE:
			if central_aberta:
				_fechar_central()
			elif state != GameDef.State.IDLE:
				_entrar_em_abertura()
				_show_notice("RODADA CANCELADA")
			get_viewport().set_input_as_handled()
			return
		if central_aberta:
			if event.keycode == KEY_T:
				_teste_de_golpe()
			# Setas e Page Up/Down rolam a página. O gabinete não tem
			# mouse; o teclado que o técnico pluga para configurar tem.
			elif event.keycode == KEY_DOWN:
				_rolar(ROLA_SETA)
			elif event.keycode == KEY_UP:
				_rolar(-ROLA_SETA)
			elif event.keycode == KEY_PAGEDOWN:
				_rolar(CENTRAL_JANELA * 0.8)
			elif event.keycode == KEY_PAGEUP:
				_rolar(-CENTRAL_JANELA * 0.8)
			elif event.keycode == KEY_HOME:
				central_rolagem = 0.0
			elif event.keycode == KEY_END:
				central_rolagem = _rolagem_maxima()
			get_viewport().set_input_as_handled()
			return
		# TECLADO É BANCADA. Num salão os comandos entram pelos botões do
		# gabinete ou pela serial; deixar 5/C e 1/Enter valendo sempre é
		# deixar um teclado esquecido no armário virar crédito de graça.
		if event.keycode in [KEY_5, KEY_C]:
			if _simulador_liberado():
				_add_credit()
			get_viewport().set_input_as_handled()
			return
		if event.keycode in [KEY_1, KEY_ENTER, KEY_KP_ENTER]:
			if _simulador_liberado():
				_pressionou_start()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventJoypadButton:
		_botao_do_gabinete(event as InputEventJoypadButton)
		return

	if central_aberta and not calib_ativo and event is InputEventMouseButton and event.pressed:
		var roda := event as InputEventMouseButton
		if roda.button_index == MOUSE_BUTTON_WHEEL_UP:
			_rolar(-ROLA_RODA)
			return
		if roda.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_rolar(ROLA_RODA)
			return

	if central_aberta and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if calib_ativo:
			_click_calibracao(event.position)
		else:
			_click_central(event.position)

## OS ATALHOS DE TECLADO (5/C PARA CRÉDITO, 1/ENTER PARA START) SÃO
## FERRAMENTA DE TÉCNICO, NUNCA DE SALÃO.
##
## Só respondem com a Central aberta na frente de quem mexe na máquina.
## Fora dela, START e CRÉDITO só chegam pelos botões do gabinete ou pela
## serial — um teclado esquecido no armário não pode virar crédito de
## graça, e o soco em si só existe vindo do MPU-6050.
func _simulador_liberado() -> bool:
	return central_aberta

## UM APERTO NA PLACA ZERO DELAY.
##
## Três coisas acontecem aqui, nesta ordem: capturar um mapeamento em
## curso, recusar repique, e só então agir. Soltar o botão nunca faz
## nada — processar solta e aperta dobraria todo comando.
func _botao_do_gabinete(evento: InputEventJoypadButton) -> void:
	if not evento.pressed:
		return
	var nome := Input.get_joy_name(evento.device)
	var guid := Input.get_joy_guid(evento.device)

	# 1) A CENTRAL ESTÁ ESPERANDO ESTE APERTO?
	if central_aberta and not mapeando.is_empty():
		_gravar_botao(evento.button_index, guid, nome)
		return
	if central_aberta:
		return

	var agora := Time.get_ticks_msec()
	if _combina(botao_start, evento.button_index, guid):
		if agora - ultimo_start_ms < REPIQUE_MS:
			return
		ultimo_start_ms = agora
		contador_start += 1
		_pressionou_start()
	elif _combina(botao_credito, evento.button_index, guid):
		if agora - ultimo_credito_ms < REPIQUE_MS:
			return
		ultimo_credito_ms = agora
		contador_credito += 1
		_add_credit()

## Grava o botão capturado no papel que a Central pediu.
##
## O MESMO BOTÃO NÃO PODE ASSUMIR OS DOIS PAPÉIS. Numa máquina em que
## START e CRÉDITO fossem o mesmo aperto, cada partida consumiria uma
## ficha e começaria junto — ou nenhuma das duas coisas aconteceria na
## hora certa. Recusar é melhor do que aceitar e deixar a máquina
## indefinida.
func _gravar_botao(indice: int, guid: String, nome: String) -> void:
	var outro := botao_credito if mapeando == "start" else botao_start
	if _combina(outro, indice, guid):
		_show_notice("ESSE BOTÃO JÁ É O OUTRO COMANDO — ESCOLHA OUTRO")
		sons.play("error", -6.0)
		return
	var mapa := {"guid": guid, "index": indice, "nome": nome}
	if mapeando == "start":
		botao_start = mapa
		contador_start = 0
	else:
		botao_credito = mapa
		contador_credito = 0
	mapeando = ""
	sons.play("menu", -8.0)
	_show_notice("BOTÃO %d GRAVADO EM %s" % [indice, "START" if mapa == botao_start else "CRÉDITO"])
	_salvar()

## Um aperto combina com um mapeamento quando o índice bate e o controle
## também — ou quando ainda não há controle gravado, caso em que o índice
## sozinho decide. É esse "ou" que faz os padrões de fábrica servirem de
## rede antes de alguém mapear qualquer coisa.
func _combina(mapa: Dictionary, indice: int, guid: String) -> bool:
	if int(mapa.get("index", -1)) != indice:
		return false
	var esperado := str(mapa.get("guid", ""))
	return esperado.is_empty() or esperado == guid

func _mapa_de_botao(bruto: Variant, indice_padrao: int) -> Dictionary:
	var d: Dictionary = bruto if bruto is Dictionary else {}
	return {
		"guid": str(d.get("guid", "")),
		"index": int(d.get("index", indice_padrao)),
		"nome": str(d.get("nome", "")),
	}

func _pressionou_start() -> void:
	## START faz uma coisa só em cada tela, e é sempre "seguir em frente".
	match state:
		GameDef.State.IDLE:
			_iniciar_rodada()
		GameDef.State.RESULT:
			# Só depois do veredito: apertar no meio da contagem cortaria
			# justamente o momento pelo qual o cliente pagou.
			if verdict_time >= 0.0:
				_iniciar_rodada()

func _iniciar_rodada() -> void:
	if game_mode == "credit":
		if credits <= 0:
			# NEGADO TEM SOM PRÓPRIO, e não o de erro genérico: faltar
			# ficha não é defeito, e quem ouve tem de entender a
			# diferença sem ler a tela.
			_show_notice("INSIRA 1 CRÉDITO")
			sons.play("start_negado", -3.0)
			aviso_de_credito = 0.0
			return
		credits -= 1
		credito_gasto = true
	_discard_round_photo()
	intro_active = false
	sons.stop("score_loop")
	state = GameDef.State.COUNTDOWN
	_iniciar_transicao()
	posicao_no_ranking = 0
	state_time = 0.0
	countdown_left = 3.0
	last_count = 3
	result_score = 0
	result_photo_path = ""
	pose_finished = false
	# A CONTAGEM ESPERA A CÂMERA (mas o OBTURADOR NÃO ABRE AQUI MAIS —
	# ver o comentário grande em `_processar_contagem`, logo abaixo de
	# onde a contagem entra na reta final).
	#
	# Contar 3-2-1 enquanto a webcam ainda está subindo é gastar a pose
	# inteira esperando: quando a contagem zera, a ponte às vezes acabou
	# de entregar o primeiro quadro, e a foto sai do nada ou não sai. A
	# espera é o conserto óbvio, e é o que o operador pediu.
	espera_da_camera = 0.0
	aguardando_camera = camera_enabled and camera_service != null and not camera_service.pronta()
	_obturador_tardio_aberto = false
	photo_retained = false
	ranking_announced = false
	_ato_assentou = false
	_ato_festejou = false
	displayed_score = 0.0
	fx.limpar()
	clarao = 1.0
	tremor = 14.0
	sons.play("start")
	sons.music(-24.0)
	moldura.set_estado(LedFrame.CONTAGEM)
	fundo.matiz = Color(0, 0, 0, 0)
	_salvar()

## DEVOLVE A FICHA DA RODADA QUE NÃO ACONTECEU.
##
## Só em modo ficha, e só uma vez: quem jogou de graça não tem o que
## receber de volta, e devolver duas vezes seria fabricar crédito.
func _devolver_credito() -> void:
	if not credito_gasto:
		return
	credito_gasto = false
	if game_mode != "credit":
		return
	credits = mini(credits + 1, GameDef.CREDITOS_MAX)
	_salvar()
	_show_notice("TEMPO ESGOTADO — CRÉDITO DEVOLVIDO  •  SALDO %02d" % credits)

func _entrar_em_abertura() -> void:
	# A volta para a abertura também é uma troca de tela, e sem cortina
	# ela era a mais seca de todas: o Top 20 sumia e a marca aparecia.
	if not intro_active:
		_iniciar_transicao()
	_discard_round_photo()
	abertura_chegada = 1.0
	# Corta os efeitos da rodada e deixa a música da abertura no ar. Antes
	# aqui era `silence()`, que também matava a música: a tela que fica
	# ligada o dia inteiro chamando gente era a única muda do jogo.
	sons.attract(-16.0)
	state = GameDef.State.IDLE
	state_time = 0.0
	verdict_time = -1.0
	result_time = 0.0
	posicao_no_ranking = 0
	result_photo_path = ""
	# NÃO SE APAGA MAIS O CACHE INTEIRO AQUI.
	#
	# Isto rodava a cada volta para a abertura -- ou seja, depois de
	# CADA rodada jogada -- e jogava fora as fotos de TODO o Top 20,
	# não só a da rodada que terminou. O resultado: a tabela travava ao
	# aparecer não uma vez por dia, mas uma vez por partida, porque
	# tinha de decodificar de novo do zero as vinte fotos toda vez.
	# `_discard_round_photo()`, chamada uma linha acima, já cuida da
	# única foto que de fato precisa sumir -- a da própria rodada, e só
	# quando ela não entrou no ranking.
	fx.limpar()
	moldura.set_estado(LedFrame.PARADA)
	fundo.matiz = Color(0, 0, 0, 0)

func _discard_round_photo() -> void:
	if not photo_retained and not result_photo_path.is_empty():
		RankingStore.delete_photo(result_photo_path)
		# O ARQUIVO SOME DO DISCO: a textura em cache para ele vira lixo
		# que nunca mais vai ser pedido de novo (o caminho tem o
		# microssegundo da captura, nunca se repete). Tirando-a do
		# cache aqui, e só ela -- não a tabela inteira -- a memória não
		# cresce sem limite e o resto do Top 20 continua pronto na
		# tela seguinte.
		_photo_cache.erase(result_photo_path)
	result_photo_path = ""
	photo_retained = false

func _add_credit() -> void:
	credits = mini(credits + 1, GameDef.CREDITOS_MAX)
	sons.play("credit")
	fx.faiscas(Vector2(540, 1300), 22, Paleta.VERDE, 420.0)
	_show_notice("CRÉDITO ADICIONADO  •  SALDO %02d" % credits)
	_salvar()

# ======================================================================
# IMPACTO E VEREDITO
# ======================================================================
func _registrar_impacto(pontos: int, velocidade: float, simulado: bool) -> void:
	## O soco aterrissou: meio segundo de impacto puro, e só então o
	## placar começa a subir. Sem esse intervalo o golpe e o número
	## chegam juntos e nenhum dos dois brilha.
	# A ficha foi usada de verdade: daqui em diante não há o que devolver.
	credito_gasto = false
	result_score = clampi(pontos, 0, GameDef.SCORE_MAX)
	result_speed = maxf(velocidade, 0.0)
	result_simulado = simulado
	state = GameDef.State.MEASURING
	state_time = 0.0
	var forca := float(result_score) / float(GameDef.SCORE_MAX)
	var alvo := _alvo()
	moldura.impacto(0.4 + forca * 0.6)
	sons.play("hit", 1.5)
	sons.play("subgrave", -4.0)
	sons.stop("charge")
	# A TRILHA SAI DA FRENTE DO GOLPE. Não para — abaixa e volta sozinha,
	# porque parar e recomeçar a música a cada soco é o que faz uma
	# máquina parecer travada entre uma rodada e outra.
	sons.duck(14.0, 2.2)
	# O NÍVEL MANDA NO ESPETÁCULO. Um impacto leve e um soco perfeito não
	# podem sacudir a máquina do mesmo jeito, e é a receita do nível que
	# diz quanto de cada coisa entra.
	pancada_nivel = ScoreTier.de(result_score)
	var receita := ImpactDirector.golpe(fx, alvo, pancada_nivel, CORES_FESTA)
	tremor = float(receita["tremor"])
	clarao = float(receita["clarao"])
	hitstop_left = float(receita["hitstop"])
	zoom_alvo = float(receita["zoom"])
	zoom_impacto = float(receita["zoom"])
	pancada_tempo = 0.0
	pancada_forca = forca
	plays += 1
	var origem := "SIMULAÇÃO" if simulado else "MPU-6050"
	posicao_no_ranking = _entrar_no_ranking(result_score, result_photo_path, origem)
	photo_retained = posicao_no_ranking > 0
	# A TABELA SÓ APARECE 2,5 s (NO MÍNIMO) DEPOIS DAQUI. Tempo de sobra
	# para o pool de linhas decodificar qualquer foto do Top 20 que
	# ainda não estava em cache, antes de a tela precisar dela de
	# verdade.
	_prewarm_fotos_do_ranking()
	statistics = StatisticsStore.record(
		statistics, result_score,
		GameDef.faixa_de(result_score),
		posicao_no_ranking > 0
	)
	_salvar()

func _disparar_veredito() -> void:
	sons.stop("score_loop")
	sons.music(-28.0)
	## O momento em que a máquina diz quanto valeu o soco. Um por golpe.
	verdict_time = 0.0
	proximo_fogo = 0.0
	var classe := GameDef.classificar(result_score)
	var cor: Color = classe["cor_faixa"]
	moldura.set_estado(LedFrame.RESULTADO, cor)
	# A tela inteira toma a cor da faixa, de leve: o veredito chega ao
	# canto do olho antes de a pessoa terminar de ler a palavra.
	fundo.matiz = Color(cor, 0.10)
	var alvo := _alvo()

	# O SOM E A COMEMORAÇÃO SÃO DO NÍVEL, não da faixa grossa.
	#
	# Antes três faixas decidiam por oito níveis, e NOCAUTE, PESO-PESADO,
	# LENDÁRIO e SOCO PERFEITO caíam todos no mesmo bloco: mesma
	# explosão, mesmo som, só a palavra mudando. Era exatamente o que a
	# pessoa que joga duas vezes seguidas percebe.
	var nivel: Dictionary = classe["nivel"]
	sons.play(str(nivel["som"]), 0.5)
	# O veredito é a fala da máquina: a trilha desce por todo o tempo em
	# que o nome do nível está sendo anunciado.
	sons.duck(16.0, 3.0)
	var receita := ImpactDirector.golpe(fx, alvo, nivel, CORES_FESTA)
	tremor = maxf(tremor, float(receita["tremor"]) * 0.8)
	clarao = maxf(clarao, float(receita["clarao"]) * 0.7)

	if posicao_no_ranking == 1:
		for sound in ["win", "medium", "lose", "legendary"]:
			sons.stop(sound)
		sons.play("record", -2.0)

# ======================================================================
# ASSISTENTE DE CALIBRAÇÃO
# ======================================================================
## CALIBRAR É MEDIR A MÁQUINA, NÃO ADIVINHAR NÚMEROS.
##
## Cada gabinete responde diferente: o saco, a mola, onde o sensor foi
## parafusado, o quanto o pé da máquina cede. Regular isso por tentativa
## e erro nos passos de − e + significa descobrir que errou depois de a
## fila reclamar. O assistente mede: quatro passos, cinco golpes fracos,
## cinco fortes, e a conta sai por percentis em `Calibracao`.
const CALIB_PASSOS := ["REPOUSO", "GOLPES FRACOS", "GOLPES FORTES", "SUGESTÃO"]
const CALIB_REPOUSO_S := 4.0
const CALIB_BOTOES := {
	"calib_avancar": Rect2(560, 1600, 400, 72),
	"calib_repetir": Rect2(120, 1600, 400, 72),
	"calib_salvar": Rect2(560, 1690, 400, 72),
	"calib_cancelar": Rect2(120, 1690, 400, 72),
}

var calib_ativo := false
var calib_passo := 0
var calib_repouso_left := 0.0
var calib_ruido := 0.0
var calib_fracos: Array[float] = []
var calib_fortes: Array[float] = []
var calib_picos: Array[float] = []
var calib_sugestao: Dictionary = {}

func _abrir_calibracao() -> void:
	calib_ativo = true
	calib_passo = 0
	calib_repouso_left = CALIB_REPOUSO_S
	calib_ruido = 0.0
	calib_fracos.clear()
	calib_fortes.clear()
	calib_picos.clear()
	calib_sugestao = {}
	_show_notice("CALIBRAÇÃO: DEIXE O SACO PARADO")

func _fechar_calibracao() -> void:
	calib_ativo = false
	calib_sugestao = {}

## O relógio do passo de repouso. Só ele corre sozinho; os outros esperam
## golpe, e golpe não tem hora.
func _processar_calibracao(delta: float) -> void:
	if not calib_ativo or calib_passo != 0:
		return
	calib_repouso_left = maxf(0.0, calib_repouso_left - delta)
	if calib_repouso_left <= 0.0:
		calib_passo = 1
		sons.play("menu", -8.0)

## Um golpe chegou durante a calibração.
##
## Ele NÃO vira pontuação, não conta partida e não entra no ranking: a
## Central está aberta e a máquina está sendo medida, não jogada.
func _calibracao_recebeu(velocidade: float, pico: float) -> void:
	match calib_passo:
		0:
			# Em repouso, qualquer coisa que chegue é ruído — e o ruído é
			# justamente o que se quer medir.
			calib_ruido = maxf(calib_ruido, pico)
		1:
			calib_fracos.append(velocidade)
			calib_picos.append(pico)
			sons.play("tick", -6.0)
			if calib_fracos.size() >= Calibracao.AMOSTRAS:
				calib_passo = 2
				sons.play("menu", -8.0)
		2:
			calib_fortes.append(velocidade)
			calib_picos.append(pico)
			sons.play("tick", -3.0)
			if calib_fortes.size() >= Calibracao.AMOSTRAS:
				calib_passo = 3
				calib_sugestao = Calibracao.sugerir(calib_fracos, calib_fortes, calib_picos, calib_ruido)
				sons.play("record", -6.0)

func _click_calibracao(p: Vector2) -> void:
	if CALIB_BOTOES["calib_cancelar"].has_point(p):
		_fechar_calibracao()
		_show_notice("CALIBRAÇÃO CANCELADA — NADA FOI MUDADO")
	elif CALIB_BOTOES["calib_repetir"].has_point(p):
		_abrir_calibracao()
	elif CALIB_BOTOES["calib_avancar"].has_point(p):
		# Pular à mão serve para quem já tem o número na cabeça e só quer
		# a parte seguinte. Nunca inventa amostra: pular deixa o passo com
		# o que colheu, e a sugestão sai do que existe.
		if calib_passo == 0:
			calib_repouso_left = 0.0
		elif calib_passo < 3:
			calib_passo += 1
			if calib_passo == 3:
				calib_sugestao = Calibracao.sugerir(calib_fracos, calib_fortes, calib_picos, calib_ruido)
	elif CALIB_BOTOES["calib_salvar"].has_point(p):
		if calib_sugestao.is_empty():
			return
		hit_min_speed = float(calib_sugestao["vmin"])
		hit_max_speed = float(calib_sugestao["vmax"])
		sensor_vmin = hit_min_speed
		sensor_amin = float(calib_sugestao["amin"])
		_aplicar_faixas()
		_salvar()
		# O firmware precisa saber também: é ele que decide o que virar
		# HIT antes de qualquer coisa chegar ao jogo.
		_enviar_config()
		_fechar_calibracao()
		_show_notice("CALIBRAÇÃO SALVA E ENVIADA AO SENSOR")

func _draw_calibracao() -> void:
	var caixa := Rect2(60, 300, 960, 1500)
	_placa(caixa, 22.0, Paleta.CARTAO_BORDA)
	_placa(caixa.grow(-5.0), 19.0, Color("240810"))
	_texto_arcade("CALIBRAÇÃO", 396.0, 62, Paleta.AMBAR, LARGURA_UTIL)

	# A trilha dos quatro passos, com o atual aceso.
	for i in range(CALIB_PASSOS.size()):
		var r := Rect2(110.0 + float(i) * 220.0, 440.0, 200.0, 54.0)
		var feito := i < calib_passo
		var atual := i == calib_passo
		var cor: Color = Paleta.VERDE if feito else (Paleta.AMBAR if atual else Color("4a1420"))
		_cartao(r, cor if (feito or atual) else Color("1c060c"), Paleta.CARTAO_BORDA, 1.0, 2.0)
		_texto(
			str(CALIB_PASSOS[i]), r.position.y + 34.0, 15,
			Color("2b0a13") if (feito or atual) else Paleta.TINTA_LEVE,
			HORIZONTAL_ALIGNMENT_CENTER, r.position.x, r.size.x
		)

	match calib_passo:
		0:
			_texto_arcade("NÃO ENCOSTE NO SACO", 620.0, 56, Color.WHITE, LARGURA_UTIL)
			_rotulo("medindo o ruído de repouso do sensor", 690.0, Paleta.TINTA_FRACA)
			_texto_arcade("%.1f s" % calib_repouso_left, 820.0, 96, Paleta.AMBAR, LARGURA_UTIL)
			_rotulo("maior pico visto: %.2f g" % calib_ruido, 900.0, Paleta.CIANO)
		1:
			_passo_de_golpes("CINCO GOLPES FRACOS", "bata de leve, como quem testa", calib_fracos)
		2:
			_passo_de_golpes("CINCO GOLPES FORTES", "bata com tudo, como o melhor cliente", calib_fortes)
		_:
			_resultado_da_calibracao()

	var pode_avancar := calib_passo < 3
	_botao(CALIB_BOTOES["calib_avancar"], "PULAR ESTE PASSO" if pode_avancar else "—", false, Paleta.CIANO, 19)
	_botao(CALIB_BOTOES["calib_repetir"], "COMEÇAR DE NOVO", false, Paleta.ROXO, 19)
	_botao(
		CALIB_BOTOES["calib_salvar"], "SALVAR E ENVIAR AO SENSOR",
		not calib_sugestao.is_empty(), Paleta.VERDE, 18
	)
	_botao(CALIB_BOTOES["calib_cancelar"], "CANCELAR", false, Paleta.VERMELHO, 19)

func _passo_de_golpes(titulo: String, dica: String, amostras: Array) -> void:
	_texto_arcade(titulo, 600.0, 52, Color.WHITE, LARGURA_UTIL)
	_rotulo(dica, 664.0, Paleta.TINTA_FRACA)
	# Uma casa por golpe: a pessoa que está batendo vê quantos faltam sem
	# precisar contar de cabeça enquanto bate.
	for i in range(Calibracao.AMOSTRAS):
		var r := Rect2(180.0 + float(i) * 148.0, 730.0, 128.0, 128.0)
		var tem := i < amostras.size()
		_cartao(r, Paleta.AMBAR if tem else Color("1c060c"), Paleta.CARTAO_BORDA, 1.0, 2.0)
		_texto(
			"%.1f" % float(amostras[i]) if tem else "—", r.position.y + 76.0, 26,
			Color("2b0a13") if tem else Paleta.TINTA_LEVE,
			HORIZONTAL_ALIGNMENT_CENTER, r.position.x, r.size.x
		)
	_rotulo("m/s medidos pelo sensor", 900.0, Paleta.CIANO)

func _resultado_da_calibracao() -> void:
	if calib_sugestao.is_empty():
		_texto_arcade("SEM AMOSTRAS SUFICIENTES", 620.0, 44, Paleta.VERMELHO, LARGURA_UTIL)
		_rotulo("volte e registre os golpes", 690.0, Paleta.TINTA_FRACA)
		return
	_texto_arcade("SUGESTÃO", 580.0, 52, Paleta.VERDE, LARGURA_UTIL)
	var linhas := [
		["VELOCIDADE MÍNIMA", "%.1f m/s" % float(calib_sugestao["vmin"]), str(calib_sugestao["porque_vmin"])],
		["VELOCIDADE MÁXIMA", "%.1f m/s" % float(calib_sugestao["vmax"]), str(calib_sugestao["porque_vmax"])],
		["SENSIBILIDADE", "%.1f g" % float(calib_sugestao["amin"]), str(calib_sugestao["porque_amin"])],
	]
	for i in range(linhas.size()):
		var y := 660.0 + float(i) * 118.0
		_cartao(Rect2(120, y - 40.0, 840, 100), Color("1c060c"), Paleta.CARTAO_BORDA, 1.0, 1.5)
		_texto(str(linhas[i][0]), y, 20, Paleta.TINTA_FRACA, HORIZONTAL_ALIGNMENT_LEFT, 150.0, 400.0)
		_texto(str(linhas[i][1]), y, 30, Paleta.AMBAR, HORIZONTAL_ALIGNMENT_RIGHT, 150.0, 780.0)
		_texto(str(linhas[i][2]), y + 30.0, 14, Paleta.TINTA_LEVE, HORIZONTAL_ALIGNMENT_LEFT, 150.0, 780.0)

	# A CURVA QUE VAI VALER, desenhada antes de salvar. É o único jeito de
	# alguém discordar da sugestão com fundamento.
	_rotulo("A CURVA COM ESTES NÚMEROS", 1070.0, Paleta.CREME)
	var antes_min := hit_min_speed
	var antes_max := hit_max_speed
	hit_min_speed = float(calib_sugestao["vmin"])
	hit_max_speed = float(calib_sugestao["vmax"])
	_curva_desenhada(Rect2(120, 1100, 840, 180))
	hit_min_speed = antes_min
	hit_max_speed = antes_max
	_apoio(
		"salvando, os valores vão para a máquina E para o firmware do sensor",
		1352.0, Paleta.TINTA_FRACA
	)

# ======================================================================
# SERIAL (MPU-6050 via GdSerial — protocolo V2)
# ======================================================================
func _iniciar_serial(evitar := "") -> void:
	_soltar_link()
	link = SerialLink.create_best(evitar)
	link.line_received.connect(_on_serial_line)
	link.opened.connect(_on_serial_opened)
	link.closed.connect(_on_serial_closed)
	# Cada caminho novo começa com a ficha limpa: fila do zero, porta
	# fixada com crédito de novo, e o relógio da vigilância zerado.
	porta_atual = ""
	ultimo_sinal_ms = -1
	placa_respondeu = false
	_porta_da_vez = 0
	_varreduras = 0
	_falhas_da_porta_fixa = 0
	_porta_confirmada = false
	_caminho_provado = false
	# `_cega_liberada` NÃO é zerada aqui de propósito: ver o comentário
	# dela. O que a máquina descobriu sobre si mesma não se esquece na
	# troca de caminho.
	_fila_de_portas = PackedStringArray()
	_caminho_desde = animation_time
	_proxima_escolha_de_caminho = animation_time + SEGUNDOS_ATE_TROCAR_DE_CAMINHO
	if not link.available():
		# NEM A EXTENSÃO NATIVA, NEM A PONTE POR PROCESSO.
		#
		# Antes desta mensagem o jogo dizia apenas "SEM EXTENSÃO SERIAL" e
		# calava — e quem estava na frente da máquina não tinha como saber
		# se faltava um arquivo, se o Windows recusou o PowerShell ou se o
		# cabo estava solto. Agora a frase diz o que a tentativa devolveu.
		#
		# E não é mais o fim da linha: `_poll_serial` continua batendo, e
		# passado o prazo o jogo REFAZ a escolha do caminho. Uma máquina
		# em que o PowerShell demorou a subir, ou em que o cabo USB chegou
		# depois, se conserta sozinha em vez de esperar por alguém.
		var motivo := link.motivo_da_falta()
		serial_status = "SEM CAMINHO ATÉ O ARDUINO — PROCURANDO OUTRO…"
		if not motivo.is_empty():
			serial_status += " (%s)" % motivo
		proxima_tentativa = animation_time + 1.0
		return
	_tentar_conectar()

## Desliga o backend anterior antes de escolher outro. Sem isto os sinais
## do backend velho continuariam chegando no jogo depois da troca, e duas
## camadas seriais falariam ao mesmo tempo sobre portas diferentes.
func _soltar_link() -> void:
	if link == null:
		return
	if link.line_received.is_connected(_on_serial_line):
		link.line_received.disconnect(_on_serial_line)
	if link.opened.is_connected(_on_serial_opened):
		link.opened.disconnect(_on_serial_opened)
	if link.closed.is_connected(_on_serial_closed):
		link.closed.disconnect(_on_serial_closed)
	link.close_port()
	link.encerrar()
	link = null

## O sensor está falando com a máquina? Decide o que o cliente vê: com o
## Arduino ligado, a tela não mostra tecla nenhuma; na bancada, mostra.
func _sensor_ligado() -> bool:
	return link != null and link.is_open() and placa_respondeu

## A PORTA CERTA SE DESCOBRE TENTANDO — não abrindo a primeira da lista.
##
## AQUI ESTAVA O "O ARDUINO NÃO FAZ NADA". O jogo pegava
## `portas_visiveis[0]`, abria, e ficava esperando. Num PC de gabinete
## quase nunca há uma porta só: o Windows inventa COM3 e COM4 para o
## Bluetooth, o leitor de cartão traz a dele. Abrindo a errada, o READY
## nunca chega — e o jogo NUNCA TENTAVA OUTRA. Ficava a noite inteira em
## "AGUARDANDO READY" numa porta que não tem placa nenhuma, com START e
## CRÉDITO mortos.
##
## Agora a lista é uma fila: abre, espera o tempo de a placa se
## apresentar, e se ela não se apresentar, passa para a próxima. A porta
## que responder fica.
##
## TRÊS SEGUNDOS VIROU CINCO, E CINCO VIROU OITO — E O RELÓGIO MUDOU DE
## LUGAR, que é a parte que importa.
##
## Abrir a porta RESETA o Arduino (é o DTR fazendo isso, não o jogo), e
## nem todo par placa/driver reseta e reinicia depressa: um bootloader
## clássico soma até dois segundos de espera própria antes de sequer
## começar o `setup()`, e um driver CH340 genérico pode demorar mais para
## o Windows terminar de enumerar a porta. Uma paciência curta cria um
## LAÇO: a porta reseta, o Arduino ainda está de pé quando o jogo desiste
## e fecha, o fechar-reabrir reseta de novo, e a placa NUNCA tem os dois
## segundos inteiros para chegar ao `Serial.println(F("READY..."))`.
##
## Mas o relógio estava contando a coisa errada. Ele começava quando o
## jogo PEDIA a abertura — e pela ponte por processo, entre o pedido e a
## porta aberta há um cano, um PowerShell e um driver. Num PC lento, ou
## com antivírus no meio, isso sozinho passa de cinco segundos: a
## paciência acabava ANTES de a porta existir, e a máquina varria a lista
## inteira sem nunca dar a nenhuma placa a chance de responder. É o
## retrato exato de "funciona no meu PC, não funciona no outro, com a
## mesma porta": a diferença não está na porta, está em quanto tempo
## aquela máquina leva para abrir uma.
##
## Agora são dois relógios. `ESPERA_DA_CONFIRMACAO` cobra o ENCANAMENTO:
## do pedido até a porta confirmar que abriu. `PORTA_PACIENCIA` cobra a
## PLACA: da porta aberta até a primeira linha válida. Nenhum dos dois
## desconta do outro.
const PORTA_PACIENCIA := 8.0
const ESPERA_DA_CONFIRMACAO := 6.0
## Depois de tantas falhas seguidas, a porta fixada na Central deixa de
## ser exclusiva e a varredura volta a incluir todas. Ver
## `_fila_de_tentativas`.
const FALHAS_ATE_SOLTAR_A_PORTA_FIXA := 2
## Tanto tempo sem uma única linha válida e o jogo TROCA DE CAMINHO até a
## placa. É o que faz a máquina funcionar num PC onde o caminho preferido
## não presta, sem ninguém para mexer em arquivo. Ver
## `SerialLink.create_best`.
const SEGUNDOS_ATE_TROCAR_DE_CAMINHO := 40.0
var _porta_da_vez := 0

## A PORTA FIXADA É PREFERÊNCIA, NÃO CADEADO — e este foi o "gato" que
## deixou a máquina presa numa porta que não existia.
##
## Fixar a porta na Central gravava o nome no disco, e a partir dali o
## jogo tentava SÓ AQUELA PORTA, para sempre, em qualquer máquina. Num PC
## onde o Nano aparece como COM3, um "COM5" gravado noutro dia é uma
## máquina morta com a placa espetada e funcionando do lado: a fila tinha
## um item só, e esse item estava errado. Pior: o arquivo de ajustes
## sobrevive à atualização do jogo, então o defeito atravessava versões.
##
## Agora a porta fixada vai na FRENTE da fila e ganha duas tentativas
## exclusivas — o bastante para ela vencer o sorteio quando está certa. Se
## não responder nessas duas, a varredura volta a incluir todas as portas
## e a máquina acha a placa onde ela estiver. A preferência continua
## valendo (ela é sempre a primeira tentada), mas deixou de ser um
## cadeado.
func _fila_de_tentativas() -> PackedStringArray:
	var fila := PackedStringArray()
	if not porta_configurada.is_empty():
		fila.append(porta_configurada)
		if _falhas_da_porta_fixa < FALHAS_ATE_SOLTAR_A_PORTA_FIXA:
			return fila
	for porta in portas_visiveis:
		if not fila.has(porta):
			fila.append(porta)
	# A VARREDURA CEGA, o último recurso — e o que responde de vez a
	# "funcione em qualquer porta, em qualquer PC".
	#
	# Toda a fila acima depende de UMA coisa dar certo: o sistema
	# ENUMERAR as portas. E é exatamente essa a peça que falha de máquina
	# para máquina, sempre de um jeito diferente — que é por que o
	# diagnóstico não bate entre dois PCs com a mesma placa. O
	# `GetPortNames()` do Windows lê o registro e devolve vazio quando o
	# driver CH340 registrou a porta noutro lugar; a extensão nativa
	# devolve o dicionário num formato que a versão dela mudou; o
	# gerenciador de dispositivos está ocupado e a consulta volta seca.
	# Em todos esses casos a porta EXISTE, a placa está falando nela — e o
	# jogo nunca a tenta, porque ninguém lhe contou que ela está ali. Isso
	# é, ao pé da letra, a busca que nunca termina.
	#
	# A saída é não perguntar. Passada a primeira volta sem sucesso, o
	# jogo tenta os nomes de porta que EXISTEM NESTE SISTEMA POR
	# CONVENÇÃO, um por um, enumeração ou não. Porta que não existe recusa
	# na hora e sai da frente em fração de segundo, então a varredura
	# inteira custa poucos segundos — e ao fim dela não sobrou porta
	# nenhuma onde a placa pudesse estar escondida.
	if _cega_liberada:
		for porta in _portas_cegas():
			if not fila.has(porta):
				fila.append(porta)
	return fila

## OS NOMES QUE O SISTEMA USA, mesmo quando ele não os anuncia.
##
## No Windows são COM1 a COM32: acima de COM9 o nome de verdade precisa
## do prefixo `\\.\`, e é o próprio SerialPort do .NET que o põe, então
## aqui vai o nome simples. No Linux são os dois nomes que um Arduino
## recebe (ttyACM para os que têm USB nativo, ttyUSB para os clones com
## CH340/FTDI). No macOS o nome carrega um sufixo do fabricante que não
## se adivinha — lá a enumeração por glob do ajudante é a única saída, e
## ela funciona.
func _portas_cegas() -> PackedStringArray:
	var cegas := PackedStringArray()
	match OS.get_name():
		"Windows":
			for i in range(1, 33):
				cegas.append("COM%d" % i)
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			for i in range(0, 8):
				cegas.append("/dev/ttyACM%d" % i)
			for i in range(0, 8):
				cegas.append("/dev/ttyUSB%d" % i)
	return cegas

func _tentar_conectar() -> void:
	# FALHA SILENCIOSA ERA O PIOR JEITO DE FALHAR.
	#
	# A conversa com o Arduino depende de uma extensão nativa (a
	# `gdserial`, um .dll ao lado do executável). Se ela não carregar —
	# arquivo faltando na exportação, arquitetura errada, antivírus que
	# apagou o .dll, ou o runtime do Visual C++ que ela precisa e que não
	# vem no Windows limpo —, `available()` volta falso e ESTA FUNÇÃO SAÍA
	# CALADA. O resultado é uma máquina em que START e CRÉDITO simplesmente
	# não existem, sem uma palavra na tela dizendo por quê: quem está do
	# outro lado procura fio solto durante horas por causa de um arquivo.
	#
	# É também o defeito que aparece SÓ NO COMPUTADOR NOVO, porque no PC
	# de quem desenvolve a extensão está sempre lá.
	if link == null or not link.available():
		serial_status = "SEM CAMINHO ATÉ O ARDUINO — VEJA docs/PROTOCOLO_SERIAL.md"
		proxima_tentativa = animation_time + 1.0
		return
	portas_visiveis = link.list_ports()
	_fila_de_portas = _fila_de_tentativas()
	if _fila_de_portas.is_empty():
		# PROCURAR TEM DE PARECER PROCURAR. A frase era só
		# "PROCURANDO ARDUINO…", parada, igual a si mesma minuto após
		# minuto — e para quem está na frente da máquina uma frase que não
		# muda é uma busca que travou. Com o caminho em uso e o número da
		# varredura à mostra, dá para ver a máquina trabalhando, e dá para
		# dizer ao telefone o que está escrito.
		_varreduras += 1
		# Sem porta nenhuma à vista já na primeira busca, a enumeração
		# desta máquina não está servindo: solta a varredura cega agora.
		_cega_liberada = true
		serial_status = "PROCURANDO ARDUINO… (%s, busca %d, nenhuma porta à vista)" % [
			link.descricao(), _varreduras
		]
		proxima_tentativa = animation_time + 1.5
		_porta_da_vez = 0
		return
	# Dá a volta na lista: a placa pode ter sido espetada depois de a
	# máquina ligar, e a porta dela entra no fim.
	if _porta_da_vez >= _fila_de_portas.size():
		_porta_da_vez = 0
		_varreduras += 1
		# Uma volta inteira sem achar: da próxima vez a fila leva também
		# as portas que ninguém anunciou. Ver `_portas_cegas`.
		_cega_liberada = true
		_fila_de_portas = _fila_de_tentativas()
	var porta := _fila_de_portas[_porta_da_vez]
	_porta_da_vez += 1
	serial_status = "CONECTANDO %s (%d de %d, busca %d)" % [
		porta, _porta_da_vez, _fila_de_portas.size(), _varreduras + 1
	]
	_porta_confirmada = false
	_porta_pedida_em = animation_time
	_porta_aberta_em = animation_time
	if link.open_port(porta, GameDef.SERIAL_BAUD):
		porta_atual = porta
		ultimo_sinal_ms = -1
		proximo_ping = animation_time + 1.0
	else:
		serial_status = "FALHA AO ABRIR %s" % porta
		proxima_tentativa = animation_time + 0.8

## DESISTIR DESTA PORTA E PASSAR PARA A PRÓXIMA, num lugar só.
##
## Eram dois trechos parecidos e um deles esquecia de contar a falha da
## porta fixada. Um lugar só é o que garante que desistir signifique
## sempre a mesma coisa, venha a desistência do encanamento ou da placa.
func _desistir_da_porta(motivo: String) -> void:
	if not porta_configurada.is_empty() and porta_atual == porta_configurada:
		_falhas_da_porta_fixa += 1
		if _falhas_da_porta_fixa == FALHAS_ATE_SOLTAR_A_PORTA_FIXA:
			_show_notice(
				"%s NÃO RESPONDE — VARRENDO TODAS AS PORTAS" % porta_configurada
			)
	var tem_outras := _fila_de_tentativas().size() > 1
	var recado := "%s EM %s%s" % [
		motivo, porta_atual, " — TENTANDO A PRÓXIMA" if tem_outras else ""
	]
	if link != null:
		# `close_port` emite `closed`, e `_on_serial_closed` escreve
		# "DESCONECTADO" por cima. A frase que explica é a que fica.
		link.close_port()
	serial_status = recado
	proxima_tentativa = animation_time + (0.3 if tem_outras else 2.0)

func _poll_serial(_delta: float) -> void:
	if link == null:
		return
	# O BATIMENTO VEM ANTES DE QUALQUER PERGUNTA, E É INCONDICIONAL.
	#
	# AQUI ESTAVA O DEFEITO QUE MATAVA A MÁQUINA PARA SEMPRE. Estava
	# assim:
	#
	#     if link == null or not link.available():
	#         return
	#     link.poll()
	#
	# `poll()` é o único batimento do backend — é DENTRO dele que a ponte
	# por processo ressuscita o ajudante que morreu. E `available()` da
	# ponte responde falso exatamente no intervalo em que ela está caída.
	# Ou seja: no instante em que o batimento passava a ser necessário,
	# ele parava. Um ajudante que caísse uma única vez (o PowerShell
	# morrendo, o cabo USB dando uma soluçada, a troca de receita) nunca
	# mais voltava, e a tela ficava congelada em "PROCURANDO ARDUINO…" até
	# alguém reiniciar o jogo. O código de ressurreição existia, estava
	# certo, e era inalcançável.
	link.poll()
	if not link.available():
		_sem_caminho_ate_a_placa()
		return
	if _vigiar_o_caminho():
		# Trocou de caminho: o `link` daqui para baixo já é outro, e ele
		# acabou de começar a própria busca. Continuar interrogando o
		# recém-nascido no mesmo quadro só produziria uma desistência
		# imediata em cima de uma porta que ninguém chegou a abrir.
		return
	if not link.is_open():
		if animation_time >= proxima_tentativa:
			_tentar_conectar()
		return
	if not _porta_confirmada and animation_time - _porta_pedida_em > ESPERA_DA_CONFIRMACAO:
		# O PEDIDO DE ABERTURA SUMIU NO ENCANAMENTO. Não é a placa: é o
		# ajudante, o cano ou o driver. Ver `ESPERA_DA_CONFIRMACAO`.
		_desistir_da_porta("NÃO ABRIU")
		return
	if _porta_confirmada and ultimo_sinal_ms < 0 and animation_time - _porta_aberta_em > PORTA_PACIENCIA:
		# CALADA DESDE QUE ABRIU: NÃO É O ENCANAMENTO. Ver o comentário de
		# `PORTA_PACIENCIA`, acima, para o motivo do número.
		_desistir_da_porta("SEM RESPOSTA")
		return
	if ultimo_sinal_ms < 0 and animation_time >= proximo_ping:
		# Ainda não vimos o READY: cutuca a placa.
		link.send_line("PING")
		proximo_ping = animation_time + 1.0
	elif ultimo_sinal_ms >= 0 and animation_time >= proximo_ping:
		link.send_line("PING")
		proximo_ping = animation_time + 5.0
	if ultimo_sinal_ms >= 0 and Time.get_ticks_msec() - ultimo_sinal_ms > 9000:
		# NOVE SEGUNDOS CALADA NÃO PODIA SER SÓ UM AVISO NA TELA.
		#
		# Antes disto, "SEM RESPOSTA" era só texto: a porta continuava
		# aberta, o PING continuava saindo a cada cinco segundos, e se o
		# Arduino tivesse de fato travado ou o cabo USB tivesse dado uma
		# soluçada, NADA nunca mais chegava — o jogo ficava com aquele
		# aviso na tela e o soco morto até alguém reiniciar a máquina. É
		# exatamente o "se demorar um pouco, ele não lê mais": não é o
		# firmware que esquece de responder, é o jogo que nunca tenta de
		# novo depois de perceber o silêncio.
		#
		# Agora o silêncio fecha a porta e entra na MESMA fila de conexão
		# do início — reabre a mesma porta (ou a próxima, se houver mais
		# de uma), do zero, com toda a lógica de PORTA_PACIENCIA de novo.
		# Uma reconexão sozinha custa menos de um segundo e não se nota;
		# não reconectar nunca é que perde a máquina a noite inteira.
		serial_status = "SEM RESPOSTA — %s — RECONECTANDO" % porta_atual
		var recado := serial_status
		link.close_port()
		serial_status = recado
		return

## SEM CAMINHO AGORA NÃO É SEM CAMINHO PARA SEMPRE.
##
## A ponte por processo responde `available() == false` enquanto está
## ressuscitando o ajudante, e isso é normal e passa em segundos. O que
## não passa sozinho é o caso em que o caminho escolhido no arranque não
## serve nesta máquina. Passado o prazo, o jogo REFAZ a escolha — e sem o
## caminho que acabou de falhar.
func _sem_caminho_ate_a_placa() -> void:
	porta_atual = ""
	_porta_confirmada = false
	var motivo := link.motivo_da_falta()
	serial_status = "SEM CAMINHO ATÉ O ARDUINO — PROCURANDO OUTRO…"
	if not motivo.is_empty():
		serial_status += " (%s)" % motivo
	if animation_time < _proxima_escolha_de_caminho:
		return
	_trocar_de_caminho("nenhum caminho respondeu")

## O CAMINHO QUE NÃO ACHA NADA TAMBÉM TEM DE SER TROCADO — e é isto que
## faz o jogo funcionar em PC que não é o de quem o escreveu.
##
## A extensão nativa pode CARREGAR e não servir. No Windows ela depende do
## runtime do Visual C++ (VCRUNTIME140.dll), que não vem numa instalação
## limpa: onde ele falta, o .dll nem entra e a ponte assume — esse caso
## conserta-se sozinho. O caso ruim é o do meio: a extensão entra, diz que
## está viva, e nunca enumera porta nenhuma. Aí o jogo antigo ficava
## eternamente em "PROCURANDO ARDUINO…" com o outro caminho ali, do lado,
## funcionando, e ninguém para chamá-lo — porque a escolha do caminho era
## feita uma vez, no arranque, e era definitiva.
##
## Agora não é. Tanto tempo sem uma única linha válida e o jogo pede o
## OUTRO caminho. Se o outro também não der, ele volta para este. A
## máquina acaba caindo no que presta nela, sozinha.
func _vigiar_o_caminho() -> bool:
	if _caminho_provado:
		# Já entregou linha nesta máquina: é o caminho certo, ponto final.
		return false
	if sensor_presente or ultimo_sinal_ms >= 0:
		# Está trabalhando: o relógio da desconfiança não corre.
		_caminho_desde = animation_time
		return false
	if animation_time - _caminho_desde < SEGUNDOS_ATE_TROCAR_DE_CAMINHO:
		return false
	# TROCAR DE CAMINHO NO MEIO DA VARREDURA SERIA DESISTIR SEM PROCURAR.
	#
	# A troca zera a fila e recomeça do princípio. Feita antes de a
	# varredura fechar uma volta — e uma volta com a lista cega tem trinta
	# e tantas portas —, ela cortaria a busca sempre no mesmo ponto, e as
	# portas do fim da fila nunca seriam tentadas por caminho nenhum. O
	# caminho só é condenado depois de ter tido a chance inteira.
	if _varreduras < 1:
		return false
	_trocar_de_caminho("%s não achou a placa em %d s" % [
		link.descricao(), int(SEGUNDOS_ATE_TROCAR_DE_CAMINHO)
	])
	return true

func _trocar_de_caminho(motivo: String) -> void:
	var anterior := link.nome_do_caminho() if link != null else ""
	_trocas_de_caminho += 1
	_iniciar_serial(anterior)
	var agora := link.descricao() if link != null else "nenhum"
	serial_status = "TROCANDO DE CAMINHO — %s → %s" % [motivo, agora]

func _on_serial_opened(porta: String) -> void:
	porta_atual = porta
	# A PORTA CONFIRMOU. É daqui que a paciência com a PLACA começa a
	# contar, e não de quando o jogo pediu. Ver `PORTA_PACIENCIA`.
	_porta_confirmada = true
	_porta_aberta_em = animation_time
	serial_status = "AGUARDANDO READY — %s" % porta

func _on_serial_closed(_porta: String) -> void:
	# PORTA QUE NUNCA FALOU NÃO MERECE ESPERA. A fila só anda quando esta
	# pausa termina: três segundos por porta (o valor antigo) numa máquina
	# com seis portas COM é meio minuto de máquina morta em cada volta, e
	# com a varredura cega seria minutos. Uma porta que recusou ou que
	# nunca disse nada sai da frente em um terço de segundo; só a que
	# ESTAVA falando e caiu ganha o segundo inteiro, porque nesse caso a
	# pausa é para o driver soltar a porta antes de reabri-la.
	var estava_falando := ultimo_sinal_ms >= 0
	serial_status = "DESCONECTADO"
	porta_atual = ""
	ultimo_sinal_ms = -1
	_porta_confirmada = false
	placa_respondeu = false
	proxima_tentativa = animation_time + (1.0 if estava_falando else 0.35)
	if estava_falando:
		sons.play("error", -8.0)

func _on_serial_line(line: String) -> void:
	var msg := ArduinoProtocol.parse(line)
	if msg.is_empty() or str(msg.get("type", "")) == "":
		return
	ultimo_sinal_ms = Time.get_ticks_msec()
	# UMA LINHA VÁLIDA É A PROVA DE QUE ESTE CAMINHO PRESTA. Zera o
	# relógio da desconfiança: `_vigiar_o_caminho` não pode trocar o
	# caminho de uma máquina que está funcionando.
	_caminho_desde = animation_time
	_caminho_provado = true
	# QUALQUER LINHA VÁLIDA JÁ PROVA A PORTA — não só o `READY`.
	#
	# O jogo esperava o `READY` para dizer "CONECTADO", e o `READY` sai
	# UMA vez, no arranque da placa. Quando o jogo reinicia e o Arduino
	# não — a máquina ligada, o operador fechando e abrindo o jogo, ou o
	# driver que não reseta a placa ao abrir a porta — esse `READY` já
	# passou há muito. A porta certa ficava então em "AGUARDANDO READY"
	# para sempre, mesmo com a placa despejando TELEMETRY e PINS quatro
	# vezes por segundo naquela mesma porta: a máquina estava vendo os
	# dados e dizendo que não havia ninguém.
	#
	# Uma linha que o protocolo entendeu só pode ter vindo do firmware.
	# Isso é a prova, e é o bastante.
	if not placa_respondeu:
		placa_respondeu = true
		serial_status = "CONECTADO %s" % porta_atual
	match str(msg["type"]):
		"READY":
			serial_status = "CONECTADO %s" % porta_atual
			# PLACA ENCONTRADA NÃO É SENSOR ENCONTRADO.
			#
			# O firmware passou a mandar o `READY` ANTES de procurar o
			# MPU-6050, para que a máquina se apresente mesmo com o sensor
			# solto — foi assim que os botões voltaram a funcionar sem
			# sensor. Mas a chave da bancada não pode mais desligar aqui:
			# desligaria a barra de espaço numa máquina em que NÃO HÁ como
			# socar, e aí não sobraria jeito nenhum de jogar.
			#
			# Quem desliga a bancada agora é a prova de que o sensor
			# existe: o `OK,MPU` do firmware, ou o primeiro golpe medido.
			sensor_presente = false
			_enviar_config()
		"PINS":
			pino_start = bool(msg["start"])
			pino_credito = bool(msg["credit"])
		"PONG":
			if not porta_atual.is_empty() and not serial_status.begins_with("CONECTADO"):
				serial_status = "CONECTADO %s" % porta_atual
		"CALIBRATING":
			serial_status = "CALIBRANDO %d%%" % int(msg["percent"])
		"CALIBRATED":
			serial_status = "CONECTADO %s" % porta_atual
			_show_notice("SENSOR CALIBRADO")
		"BUTTON":
			# O CONTADOR SOBE SEMPRE, inclusive com a Central aberta.
			#
			# É ele que prova ao técnico que o fio está certo: aperta o
			# botão, o número sobe. Sem isso, "o botão não funciona" pode
			# ser fio solto, pino errado, placa muda ou o jogo ignorando —
			# quatro problemas com o mesmo sintoma. Com o contador, dois
			# deles se descartam em um segundo.
			if str(msg["button"]) == "CREDIT":
				serial_credito += 1
			else:
				serial_start += 1
			if central_aberta:
				return
			if str(msg["button"]) == "CREDIT":
				_add_credit()
			else:
				_pressionou_start()
		"HIT":
			_receber_hit(msg)
		"TELEMETRY":
			telemetria = "a=(%.1f, %.1f, %.1f)g  g=(%.0f, %.0f, %.0f)°/s  pico %.1fg" % [
				msg["accel"].x, msg["accel"].y, msg["accel"].z,
				msg["gyro"].x, msg["gyro"].y, msg["gyro"].z,
				msg["peak_g"],
			]
		"SATURATION":
			# SATURAÇÃO NÃO VIRA 9999. O sensor chegou ao fim da escala e
			# parou de medir: a máquina não sabe quanto aquele golpe valeu,
			# e chutar o teto seria inventar. Fica registrado para a
			# Central, que é onde alguém pode aumentar a faixa do MPU.
			saturacao_recente = "%s às %s" % [
				str(msg["source"]), Time.get_time_string_from_system(true)
			]
			_show_notice("SATURAÇÃO NO %s — AUMENTE A FAIXA DO SENSOR" % str(msg["source"]))
		"OK":
			# `OK,MPU` é o firmware avisando que o sensor apareceu — no
			# arranque, ou depois de alguém encaixar de volta um fio do
			# I2C com a máquina ligada.
			if str(msg.get("detail", "")) == "MPU":
				_sensor_apareceu()
		"ERROR":
			if str(msg["code"]) == "NO_MPU":
				# SEM SENSOR A MÁQUINA CONTINUA DE PÉ: botões e crédito
				# seguem funcionando pela serial; só o soco depende do
				# MPU-6050. Dizer isso é melhor do que dizer "erro".
				sensor_presente = false
				serial_status = "PLACA OK, SEM SENSOR — CONFIRA SDA/SCL"
				_show_notice("SENSOR NÃO ENCONTRADO — CONFIRA O FIO SDA/SCL")
			else:
				_show_notice("ERRO DO FIRMWARE: %s" % str(msg["code"]))
			sons.play("error", -8.0)

## TEMPO MORTO ENTRE DOIS GOLPES ACEITOS, em milissegundos.
##
## Depois do impacto o saco balança, e o MPU-6050 vê o balanço como uma
## sequência de eventos menores. Sem tempo morto, um soco vira três — e o
## segundo, mais fraco, seria o que ficaria no placar.
const TEMPO_MORTO_MS := 900
## Um soco de verdade dura dezenas de milissegundos. Um toque, um esbarrão
## ou um tranco no gabinete duram muito menos.
const DURACAO_MINIMA_MS := 12.0

## O SENSOR SE ANUNCIOU. É o único momento em que a máquina sabe, sozinha,
## que saiu da montagem e entrou em operação.
func _sensor_apareceu() -> void:
	if sensor_presente:
		return
	sensor_presente = true
	serial_status = "CONECTADO %s" % porta_atual

func _receber_hit(msg: Dictionary) -> void:
	# Golpe medido é a prova definitiva de que o sensor está lá, mesmo que
	# o `OK,MPU` tenha se perdido no cabo.
	_sensor_apareceu()
	var speed := float(msg["speed"])
	var pico := float(msg.get("accel", 0.0))
	var duracao := float(msg.get("duration_ms", 0.0))
	telemetria = "último evento: %.2f m/s, %.1fg, %.0f ms, eixo %s" % [
		speed, pico, duracao, str(msg.get("axis", "?"))
	]
	# 0) CALIBRANDO: o golpe vira AMOSTRA, e não pontuação. Não conta
	#    partida, não entra no ranking, não gasta ficha.
	if calib_ativo:
		_calibracao_recebeu(speed, pico)
		return
	# 1) FORA DE ARMED NÃO PONTUA. Nem na abertura, nem na foto, nem no
	#    resultado, nem com a Central aberta.
	if state != GameDef.State.ARMED or central_aberta:
		return
	# 2) UM GOLPE POR RODADA.
	if golpe_registrado:
		return
	# 3) TEMPO MORTO: o balanço do saco depois do impacto não é um golpe.
	if Time.get_ticks_msec() - ultimo_golpe_ms < TEMPO_MORTO_MS:
		return
	# 4) O EVENTO PRECISA TER FÍSICA DE SOCO. Duração e pico de aceleração
	#    não entram na nota — eles decidem se aquilo foi um soco.
	if duracao < DURACAO_MINIMA_MS:
		telemetria += "  •  recusado: curto demais"
		return
	if pico < sensor_amin:
		telemetria += "  •  recusado: pico abaixo de %.1fg" % sensor_amin
		return
	golpe_registrado = true
	ultimo_golpe_ms = Time.get_ticks_msec()
	_processar_golpe(speed, false)

## Sensor e teclado passam obrigatoriamente por esta única porta. Assim a
## régua mostrada na Central é a mesma que decide o resultado real.
func _processar_golpe(speed: float, simulado: bool) -> void:
	var pontos := ScoreCurve.points_from_speed(
		speed, hit_min_speed, hit_max_speed, score_exponent, score_dead_zone
	)
	if pontos <= 0:
		_show_notice("MOVIMENTO ABAIXO DA ZONA DE PONTUAÇÃO")
		return
	_registrar_impacto(pontos, speed, simulado)

## AS FITAS DA MÁQUINA ACOMPANHANDO O PLACAR.
##
## Vinte mensagens por segundo entupiriam a serial e atrasariam o que
## importa, que é a linha do próximo golpe. Doze é o bastante: a coluna
## sobe suave porque a própria placa interpola entre um comando e o
## seguinte.
const FITAS_INTERVALO := 0.08
var _fitas_relogio := 0.0
var _fitas_ultimo := -1.0

func _mandar_fitas(fracao: float, agora := true) -> void:
	if link == null or not link.is_open():
		return
	var f := clampf(fracao, 0.0, 1.0)
	# Sem repetir o mesmo valor: com o placar parado no fim da contagem,
	# repetir gasta serial para não dizer nada.
	if not agora and is_equal_approx(f, _fitas_ultimo):
		return
	var t := float(Time.get_ticks_msec()) / 1000.0
	if t - _fitas_relogio < FITAS_INTERVALO:
		return
	_fitas_relogio = t
	_fitas_ultimo = f
	link.send_line(ArduinoProtocol.build_leds(f))

func _enviar_config() -> void:
	if link != null and link.is_open():
		link.send_line(ArduinoProtocol.build_config(
			sensor_eixo, sensor_raio, sensor_vmin, sensor_amin, hit_max_speed
		))

func _teste_de_golpe() -> void:
	## Na Central Técnica (tecla T ou botão TESTAR): se a placa está
	## ligada, pede um golpe sintético a ela; senão, simula um aqui.
	if link != null and link.is_open():
		link.send_line("TEST")
		_show_notice("TESTE SOLICITADO AO ARDUINO")
	else:
		var speed := randf_range(hit_min_speed + 1.0, hit_max_speed * 0.9)
		_show_notice("GOLPE SIMULADO — %.1f m/s" % speed)
		if state == GameDef.State.ARMED:
			_receber_hit({
				"speed": speed, "accel": maxf(sensor_amin, 8.0),
				"duration_ms": 45.0, "axis": sensor_eixo,
			})

# ======================================================================
# CENTRAL TÉCNICA (F9)
# ======================================================================
func _toggle_central() -> void:
	if central_aberta:
		_fechar_central()
	else:
		if state != GameDef.State.IDLE and state != GameDef.State.RESULT:
			_entrar_em_abertura()
		central_aberta = true
		sons.silence()
		if link != null and link.available():
			portas_visiveis = link.list_ports()
		sons.play("menu", -4.0)

func _fechar_central() -> void:
	central_aberta = false
	if state == GameDef.State.RESULT:
		sons.music(-28.0)
		if verdict_time < 0.0:
			sons.start_score_loop()
	_aplicar_faixas()
	_salvar()
	_enviar_config()
	sons.play("menu", -8.0)

## Retângulo do botão "−" de um passo.
func _passo_menos(chave: String) -> Rect2:
	var r: Rect2 = PASSOS[chave]
	return Rect2(r.position, Vector2(LADO_BOTAO, r.size.y))

## Retângulo do botão "+" de um passo.
func _passo_mais(chave: String) -> Rect2:
	var r: Rect2 = PASSOS[chave]
	return Rect2(Vector2(r.end.x - LADO_BOTAO, r.position.y), Vector2(LADO_BOTAO, r.size.y))

## Espaço livre entre os dois botões — onde o valor cabe sem encostar.
func _passo_visor(chave: String) -> Rect2:
	var r: Rect2 = PASSOS[chave]
	return Rect2(
		Vector2(r.position.x + LADO_BOTAO + 8.0, r.position.y),
		Vector2(r.size.x - LADO_BOTAO * 2.0 - 16.0, r.size.y)
	)

## Um controle só responde se estiver NA PÁGINA ABERTA. Os retângulos
## continuam existindo mesmo quando não estão desenhados, e um botão
## invisível que responde é a pior espécie de defeito: o técnico clica
## num lugar vazio e a máquina muda de comportamento.
func _visivel_na_pagina(chave: String) -> bool:
	var pagina := int(PAGINA_DO_CONTROLE.get(chave, -1))
	return pagina < 0 or pagina == central_pagina

## A JANELA QUE ROLA, dentro da Central.
##
## O cabeçalho (título, abas) e o rodapé (RESTAURAR, SALVAR, carimbo da
## build) ficam PARADOS; o miolo entre os dois é que anda. É assim que um
## aplicativo se comporta, e é a única forma de a página caber quando a
## letra cresce: sem rolagem, cada rótulo maior empurra a última seção
## para fora do painel — que é exatamente a sobreposição que se via.
const CENTRAL_TOPO := 332.0
const CENTRAL_BASE := 1762.0
const CENTRAL_JANELA := CENTRAL_BASE - CENTRAL_TOPO
## Quanto anda um giro da roda, uma seta, uma página.
const ROLA_RODA := 90.0
const ROLA_SETA := 60.0

var central_rolagem := 0.0
## A base da última seção desenhada. Medida durante o desenho, e não
## anotada numa tabela: uma tabela de alturas por página envelhece na
## primeira seção que alguém mover, e envelhece em silêncio.
var central_fundo := 0.0

## Quanto ainda há para rolar na página atual.
func _rolagem_maxima() -> float:
	return maxf(0.0, central_fundo + 30.0 - CENTRAL_BASE)

func _rolar(quanto: float) -> void:
	central_rolagem = clampf(central_rolagem + quanto, 0.0, _rolagem_maxima())

## O ponto do clique NO ESPAÇO DA PÁGINA.
##
## Controles de página vivem num papel que rolou; os três de fora
## (fechar, restaurar, salvar) estão colados na moldura. Sem esta
## distinção, rolar a página faria o clique acertar o botão de cima.
func _ponto_do_controle(chave: String, p: Vector2) -> Vector2:
	if int(PAGINA_DO_CONTROLE.get(chave, -1)) < 0:
		return p
	return p + Vector2(0.0, central_rolagem)

## Um clique acertou este controle? Junta as três perguntas que sempre
## andavam juntas: está nesta página, o papel rolou, e o ponto caiu dentro.
func _tocou(chave: String, p: Vector2) -> bool:
	if not _visivel_na_pagina(chave):
		return false
	var r: Rect2 = BOTOES_SIMPLES[chave]
	return r.has_point(_ponto_do_controle(chave, p))

func _click_central(p: Vector2) -> void:
	# As abas primeiro: elas ficam por cima de tudo.
	if ABA_RECT.has_point(p):
		central_pagina = clampi(int((p.x - ABA_RECT.position.x) / ABA_LARGURA), 0, PAGINAS.size() - 1)
		# Cada aba começa do começo. Chegar numa página nova já rolada até
		# o meio é o tipo de coisa que faz o técnico achar que faltou
		# conteúdo em cima.
		central_rolagem = 0.0
		mapeando = ""
		return
	# Passos depois: são a maioria dos cliques.
	for chave in PASSOS:
		if not _visivel_na_pagina(chave):
			continue
		if _passo_menos(chave).has_point(_ponto_do_controle(chave, p)):
			_ajustar(chave, -1)
			_salvar()
			return
		if _passo_mais(chave).has_point(_ponto_do_controle(chave, p)):
			_ajustar(chave, 1)
			_salvar()
			return

	# Um clique fora de qualquer botão cancela um mapeamento em curso:
	# quem desistiu não fica com a máquina esperando um aperto para sempre.
	var acertou := false
	for chave in BOTOES_SIMPLES:
		if _tocou(str(chave), p):
			acertou = true
			break
	if not acertou:
		mapeando = ""
		return

	if _tocou("fechar", p) or _tocou("salvar", p):
		_fechar_central()
		return
	elif _tocou("mapear_start", p):
		mapeando = "" if mapeando == "start" else "start"
		return
	elif _tocou("mapear_credito", p):
		mapeando = "" if mapeando == "credito" else "credito"
		return
	elif _tocou("modo_livre", p):
		game_mode = "free"
	elif _tocou("modo_ficha", p):
		game_mode = "credit"
	elif _tocou("eixo", p):
		var eixos := ["X", "Y", "Z"]
		sensor_eixo = eixos[(eixos.find(sensor_eixo) + 1) % 3]
	elif _tocou("enviar_config", p):
		_enviar_config()
		_show_notice("CONFIG ENVIADA AO ARDUINO")
	elif _tocou("calibrar", p):
		_abrir_calibracao()
		return
	elif _tocou("testar", p):
		_teste_de_golpe()
	elif _tocou("camera", p):
		camera_enabled = not camera_enabled
		camera_service.set_enabled(camera_enabled)
		_show_notice(camera_service.status)
	elif _tocou("forcar_ponte", p):
		camera_forcar_ponte = not camera_forcar_ponte
		camera_ponte_escolhida = true
		camera_service.forcar_ponte = camera_forcar_ponte
		camera_service.pedir_abertura()
		_show_notice(
			"INDO DIRETO PELA PONTE PYTHON" if camera_forcar_ponte
			else "TENTANDO O CAMINHO NATIVO PRIMEIRO"
		)
	elif _tocou("diagnosticar", p):
		_examinar_camera(false)
	elif _tocou("instalar_camera", p):
		_examinar_camera(true)
	elif _tocou("sondar_camera", p):
		# PROCURAR DE NOVO, e não só religar: `refresh` zera a desistência
		# e refaz a enumeração inteira. É o botão de quem acabou de
		# espetar a webcam com o jogo já aberto.
		camera_service.pedir_abertura()
		_show_notice(camera_service.estado_curto())
	elif _tocou("trocar_camera", p):
		camera_service.cycle_camera()
		# A escolha do técnico também é descoberta e também fica guardada:
		# senão o próximo boot volta ao índice antigo e ele troca de novo.
		camera_index = camera_service.selected_index
		_salvar()
		_show_notice(camera_service.status)
	elif _tocou("testar_som", p):
		# O SOCO DE TESTE DA MESA toca o impacto e o nível mais alto por
		# cima da trilha: é o pior caso de mistura, e é nele que se regula.
		sons.play("hit", 1.5)
		sons.play("subgrave", -4.0)
		sons.play("nivel_peso", 0.5)
		sons.duck(16.0, 2.5)
		_show_notice("SOCO DE TESTE — CONFIRA A MISTURA")
	elif _tocou("foto_teste", p):
		var test_path := camera_service.capture_photo()
		if test_path.is_empty():
			_show_notice(camera_service.status)
		else:
			RankingStore.delete_photo(test_path)
			_show_notice("CAPTURA DA CÂMERA APROVADA")
	elif _tocou("zerar", p):
		if not _confirmar("contadores"):
			return
		credits = 0
		plays = 0
		_show_notice("CONTADORES ZERADOS")
	elif _tocou("zerar_stats", p):
		if not _confirmar("estatisticas"):
			return
		statistics = {}
		_show_notice("ESTATÍSTICAS ZERADAS")
	elif _tocou("zerar_ranking", p):
		if not _confirmar("ranking"):
			return
		RankingStore.clear_photos(ranking)
		ranking.clear()
		_photo_cache.clear()
		_show_notice("RANKING E FOTOS ZERADOS")
	elif _tocou("teto_efeitos", p):
		desempenho.teto = desempenho.proximo_teto()
		desempenho.aplicar_teto()
		teto_efeitos = desempenho.teto
		_show_notice("TETO DE EFEITOS: %s" % desempenho.teto)
	elif _tocou("reconectar", p):
		# RECONECTAR REFAZ A ESCOLHA INTEIRA, e não só reabre a porta.
		#
		# Era só um `close_port` seguido de `_tentar_conectar`: reabria a
		# MESMA porta pelo MESMO caminho, que é justamente o par que
		# acabou de não funcionar. Para o técnico que apertou o botão, o
		# pedido é "esquece tudo e procura de novo" — e agora é isso que
		# acontece: caminho escolhido do zero (extensão nativa ou ponte),
		# porta fixada com crédito de novo, fila inteira revarrida.
		_iniciar_serial()
		_show_notice("PROCURANDO O ARDUINO DE NOVO, DO ZERO")
	elif _tocou("padroes", p):
		game_mode = "credit"
		porta_configurada = ""
		hit_min_speed = ScoreCurve.DEFAULT_MIN_SPEED
		hit_max_speed = ScoreCurve.DEFAULT_MAX_SPEED
		score_exponent = ScoreCurve.DEFAULT_EXPONENT
		score_dead_zone = ScoreCurve.DEFAULT_DEAD_ZONE
		sensor_eixo = "X"
		sensor_raio = 0.45
		sensor_vmin = ScoreCurve.DEFAULT_MIN_SPEED
		sensor_amin = 3.5
		_show_notice("PADRÕES RESTAURADOS")
	else:
		return
	_aplicar_faixas()
	_salvar()

## Um clique num − ou + . Cada valor tem o seu passo e os seus limites,
## e o saneamento fica com `ScoreCurve.sanitize`, chamado por
## `_aplicar_faixas` logo depois de qualquer ajuste.
func _ajustar(chave: String, direcao: int) -> void:
	match chave:
		"vmin":
			hit_min_speed = clampf(
				hit_min_speed + direcao * 0.1,
				ScoreCurve.MIN_SPEED_MIN, minf(ScoreCurve.MIN_SPEED_MAX, hit_max_speed - 0.5)
			)
		"vmax":
			hit_max_speed = clampf(
				hit_max_speed + direcao * 0.5,
				maxf(ScoreCurve.MAX_SPEED_MIN, hit_min_speed + 0.5), ScoreCurve.MAX_SPEED_MAX
			)
		"curva":
			score_exponent = clampf(score_exponent + direcao * 0.05, ScoreCurve.EXPONENT_MIN, ScoreCurve.EXPONENT_MAX)
		"zona":
			score_dead_zone = clampf(score_dead_zone + direcao * 0.01, 0.0, ScoreCurve.DEAD_ZONE_MAX)
		"vol_musica":
			volume_musica = clampf(volume_musica + direcao, -40.0, 6.0)
			sons.set_volumes(volume_musica, volume_efeitos)
		"vol_efeitos":
			volume_efeitos = clampf(volume_efeitos + direcao, -40.0, 6.0)
			sons.set_volumes(volume_musica, volume_efeitos)
		"porta":
			_girar_porta(direcao)
		"raio":
			sensor_raio = clampf(sensor_raio + direcao * 0.05, 0.05, 1.50)
		"amin":
			sensor_amin = clampf(sensor_amin + direcao * 0.5, 0.5, 15.0)
	_aplicar_faixas()

## AS PORTAS QUE SE PODE FIXAR — e não só as que estão à vista.
##
## A lista era só `portas_visiveis`, e isso tornava a opção inútil
## justamente quando ela é mais necessária: com a placa desligada ou o
## driver ainda sem carregar, a COM do Nano não aparece, e não havia como
## deixá-la escolhida ESPERANDO a placa chegar. Fixar uma porta é dizer
## "é aqui que ela vai estar" — uma decisão sobre o futuro, não sobre o
## presente.
##
## No Windows entram COM1 a COM12 sempre; no Linux e no macOS a
## enumeração é confiável e a lista real basta.
func _opcoes_de_porta() -> PackedStringArray:
	var opcoes := PackedStringArray(["AUTO"])
	if OS.get_name() == "Windows":
		for i in range(1, 13):
			opcoes.append("COM%d" % i)
	for porta in portas_visiveis:
		if not opcoes.has(porta):
			opcoes.append(porta)
	# A porta guardada entra na lista mesmo que hoje ninguém a veja: sem
	# isso, abrir a Central com a placa fora do ar apagaria a escolha.
	if not porta_configurada.is_empty() and not opcoes.has(porta_configurada):
		opcoes.append(porta_configurada)
	return opcoes

func _girar_porta(direcao: int) -> void:
	var opcoes := _opcoes_de_porta()
	var atual := opcoes.find(porta_configurada if not porta_configurada.is_empty() else "AUTO")
	if atual < 0:
		atual = 0
	atual = (atual + direcao + opcoes.size()) % opcoes.size()
	var escolha := opcoes[atual]
	porta_configurada = "" if escolha == "AUTO" else escolha
	# Trocar a porta à mão vale agora, não na próxima varredura.
	if link != null and link.is_open():
		link.close_port()
	proxima_tentativa = animation_time
	_porta_da_vez = 0

func _show_notice(message: String) -> void:
	notice = message
	notice_left = 2.8

func _confirmar(action: String) -> bool:
	if confirm_action == action and animation_time <= confirm_until:
		confirm_action = ""
		return true
	confirm_action = action
	confirm_until = animation_time + 4.0
	_show_notice("CONFIRME: CLIQUE NOVAMENTE EM ATÉ 4 SEGUNDOS")
	return false

# ======================================================================
# ESTADO EM DISCO
# ======================================================================
func _carregar() -> void:
	var data := SettingsStore.load_data()
	if data.is_empty():
		return
	game_mode = str(data.get("mode", game_mode))
	credits = int(data.get("credits", credits))
	plays = int(data.get("plays", plays))
	# MIGRAÇÃO: instalações antigas guardavam um recorde só. Ele vira a
	# primeira linha do ranking, para o dono não perder a marca da casa
	# ao atualizar o software.
	var antigo := int(data.get("best_score", 0))
	# A versão gravada decide se as marcas ainda estão na escala antiga.
	# Ausente quer dizer "arquivo de antes de existir versão", ou seja,
	# escala 0 a 999 — e é essa a única vez que a conversão acontece.
	var esquema := int(data.get("ranking_schema", RankingStore.ESQUEMA_LEGADO))
	ranking = RankingStore.migrate(data.get("ranking", []), antigo, esquema)
	if esquema < RankingStore.ESQUEMA:
		# Grava a nova versão já, e não só no próximo `_salvar`: uma queda
		# de energia entre a conversão e o primeiro salvamento converteria
		# tudo de novo no religar.
		# Grava a versão nova AGORA, e não só no próximo `_salvar`: uma
		# queda de energia entre a conversão e o primeiro salvamento
		# converteria tudo outra vez no religar.
		_converteu_esquema = true
	porta_configurada = str(data.get("port", porta_configurada))
	hit_min_speed = float(data.get("hit_min_speed", hit_min_speed))
	hit_max_speed = float(data.get("hit_max_speed", hit_max_speed))
	score_exponent = float(data.get("score_exponent", score_exponent))
	score_dead_zone = float(data.get("score_dead_zone", score_dead_zone))
	sensor_eixo = str(data.get("sensor_eixo", sensor_eixo))
	sensor_raio = float(data.get("sensor_raio", sensor_raio))
	sensor_vmin = float(data.get("sensor_vmin", sensor_vmin))
	sensor_amin = float(data.get("sensor_amin", sensor_amin))
	volume_musica = float(data.get("volume_musica", volume_musica))
	volume_efeitos = float(data.get("volume_efeitos", volume_efeitos))
	botao_start = _mapa_de_botao(data.get("botao_start", {}), 6)
	botao_credito = _mapa_de_botao(data.get("botao_credito", {}), 4)
	camera_enabled = bool(data.get("camera_enabled", camera_enabled))
	camera_index = int(data.get("camera_index", camera_index))
	camera_backend = str(data.get("camera_backend", camera_backend))
	camera_python = str(data.get("camera_python", camera_python))
	teto_efeitos = str(data.get("teto_efeitos", teto_efeitos))
	desempenho.teto = teto_efeitos
	desempenho.aplicar_teto()
	camera_python_args = str(data.get("camera_python_args", camera_python_args))
	camera_ponte_escolhida = bool(data.get("camera_ponte_escolhida", false))
	if camera_ponte_escolhida:
		camera_forcar_ponte = bool(data.get("camera_forcar_ponte", camera_forcar_ponte))
	camera_mirrored = bool(data.get("camera_mirrored", camera_mirrored))
	statistics = StatisticsStore.sanitize(data.get("statistics", {}))

func _salvar() -> void:
	SettingsStore.save_data({
		"mode": game_mode,
		"credits": credits,
		"plays": plays,
		"ranking": ranking,
		"ranking_schema": RankingStore.ESQUEMA,
		# Mantido para uma eventual volta a uma versão anterior do jogo.
		"best_score": _melhor(),
		"port": porta_configurada,
		"hit_min_speed": hit_min_speed,
		"hit_max_speed": hit_max_speed,
		"score_exponent": score_exponent,
		"score_dead_zone": score_dead_zone,
		"sensor_eixo": sensor_eixo,
		"sensor_raio": sensor_raio,
		"sensor_vmin": sensor_vmin,
		"sensor_amin": sensor_amin,
		"volume_musica": volume_musica,
		"volume_efeitos": volume_efeitos,
		"botao_start": botao_start,
		"botao_credito": botao_credito,
		"camera_enabled": camera_enabled,
		"camera_index": camera_index,
		"camera_backend": camera_backend,
		"camera_python": camera_python,
		"teto_efeitos": teto_efeitos,
		"camera_python_args": camera_python_args,
		"camera_forcar_ponte": camera_forcar_ponte,
		"camera_ponte_escolhida": camera_ponte_escolhida,
		"camera_mirrored": camera_mirrored,
		"statistics": statistics,
	})

# ======================================================================
# DESENHO
# ======================================================================
## Chama a cortina. `_process` cuida do resto.
func _iniciar_transicao() -> void:
	transicao = 0.0

func _draw() -> void:
	fundo.visible = true
	moldura.visible = false
	# O NOME COMEÇA ESCONDIDO A CADA QUADRO. Quem quiser mostrá-lo diz
	# isso durante este desenho; sem esta linha, o letreiro ficaria na
	# tela depois que a abertura sai, porque o nó do shader é desenhado
	# depois deste e não sabe em que estado o jogo está.
	letreiro_do_nome.esconder()
	# TREMOR E ZOOM SACODEM A TELA INTEIRA: uma transformação só, antes de
	# tudo. O zoom cresce a partir do PONTO DO SOCO e não do centro da
	# tela — crescer pelo centro afastaria a imagem justamente do lugar
	# onde a pessoa está olhando.
	_deslocamento = Vector2.ZERO
	if tremor > 0.1:
		_deslocamento = Vector2(randf_range(-tremor, tremor), randf_range(-tremor, tremor))
	var escala := Vector2.ONE * zoom_impacto
	var origem := _deslocamento + ALVO_DO_SOCO - ALVO_DO_SOCO * zoom_impacto
	if tremor > 0.1 or zoom_impacto != 1.0:
		draw_set_transform(origem, 0.0, escala)

	if state == GameDef.State.IDLE:
		if intro_active:
			ArcadeStage.intro(self, intro_time)
		else:
			_draw_show_idle()
	elif state == GameDef.State.RESULT and verdict_time >= 2.5:
		_draw_ranking_reveal()
	else:
		_draw_partida()

	fx.desenhar(self)
	_draw_pancada()
	_draw_clarao()
	_draw_alertas_graves()
	_draw_transicao()

	# A FAIXA DE AVISO SAIU DA TELA DO JOGO. Pedido explícito: um cartão
	# de "CÂMERA CONECTADA" ou "CRÉDITO ADICIONADO" surgindo por cima da
	# partida é informação de bancada, não de vitrine — quem joga não
	# precisa ler isso, e numa máquina de salão de verdade não deveria
	# ver texto de diagnóstico nenhum. `_show_notice` continua existindo
	# (a Central Técnica e o rodapé de alertas graves, logo acima, ainda
	# falam quando algo realmente importante precisa ser dito), só o
	# cartão avulso no meio da tela é que não aparece mais.

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if central_aberta:
		_draw_central()
		# O ASSISTENTE COBRE A CENTRAL. Enquanto ele está no ar, mexer nos
		# passos por baixo mudaria justamente os números que ele está
		# medindo — e o técnico veria a sugestão brigar com o que ele
		# acabou de ajustar.
		if calib_ativo:
			_draw_calibracao()

## O IMPACTO NA TELA, entregue ao diretor de efeitos.
##
## Cada nível tem o seu desenho — estrelão, rachaduras, túnel de luz,
## palco reagindo — e a receita mora em `ScoreTier`. Aqui só se decide
## QUANDO desenhar; o QUE desenhar é do diretor.
func _draw_pancada() -> void:
	if pancada_tempo < 0.0 or pancada_nivel.is_empty():
		return
	ImpactDirector.desenhar(
		self, pancada_nivel,
		clampf(pancada_tempo / ImpactDirector.PANCADA_DURACAO, 0.0, 1.0),
		_alvo(), pancada_forca
	)

## A CORTINA: uma faixa diagonal cruzando a tela, com o alvo montado nela.
##
## POR QUE DIAGONAL E POR QUE ATRAVESSANDO. Um esmaecer para o preto
## esconde a troca, mas também esconde meio segundo de máquina — e numa
## fila de fliperama meio segundo de tela preta parece travamento. Uma
## faixa que ENTRA por um lado e SAI pelo outro cobre a troca e ainda diz
## para que lado o jogo está indo.
##
## O corte é oblíquo porque o fundo do jogo já é feito de faixas
## oblíquas: a cortina passa a parecer uma peça do cenário se movendo, e
## não um retângulo estranho aparecendo por cima.
func _draw_transicao() -> void:
	if transicao < 0.0:
		return
	var t := clampf(transicao / TRANSICAO_DURACAO, 0.0, 1.0)
	var avanco := ease(t, 0.55)
	# A faixa é mais larga que a tela para cobrir o corte inteiro no meio
	# do caminho; sem isso apareceria uma fresta do jogo antigo.
	var largura := 1500.0
	var x := lerpf(-largura, TELA.x + largura, avanco)
	var inclinacao := 260.0
	var faixa := PackedVector2Array([
		Vector2(x - largura * 0.5 + inclinacao, -20.0),
		Vector2(x + largura * 0.5 + inclinacao, -20.0),
		Vector2(x + largura * 0.5 - inclinacao, TELA.y + 20.0),
		Vector2(x - largura * 0.5 - inclinacao, TELA.y + 20.0),
	])
	Traco.poligono(self, faixa, Color("b21029"))
	# Um fio de ouro na borda de ataque: é ele que dá velocidade ao gesto.
	draw_line(
		Vector2(x + largura * 0.5 + inclinacao, -20.0),
		Vector2(x + largura * 0.5 - inclinacao, TELA.y + 20.0),
		Paleta.AMBAR, 8.0, true
	)
	draw_line(
		Vector2(x - largura * 0.5 + inclinacao, -20.0),
		Vector2(x - largura * 0.5 - inclinacao, TELA.y + 20.0),
		Color(Paleta.AMBAR, 0.55), 4.0, true
	)
	# O alvo viaja montado na faixa. É a mesma marca do jogo, e é o que
	# faz a cortina pertencer a ESTA máquina e não a qualquer uma.
	var centro := Vector2(x, TELA.y * 0.5)
	if centro.x > -200.0 and centro.x < TELA.x + 200.0:
		Icones.alvo(self, centro, 108.0, Paleta.AMBAR)

## O CLARÃO DO SOCO NUM FUNDO CLARO. Lavar a tela de branco não funciona
## aqui — branco sobre quase-branco não é clarão, é nada. O golpe acende
## em ÂMBAR e escurece as bordas ao mesmo tempo: é o contraste que o olho
## lê como flash, não o brilho absoluto.
func _draw_clarao() -> void:
	if clarao <= 0.01:
		return
	draw_rect(Rect2(Vector2.ZERO, TELA), Color(Paleta.LUZ, clarao * 0.70))
	var borda := 150.0 * clarao
	var escuro := Color(Paleta.MARINHO, clarao * 0.30)
	draw_rect(Rect2(0.0, 0.0, TELA.x, borda), escuro)
	draw_rect(Rect2(0.0, TELA.y - borda, TELA.x, borda), escuro)
	draw_rect(Rect2(0.0, 0.0, borda, TELA.y), escuro)
	draw_rect(Rect2(TELA.x - borda, 0.0, borda, TELA.y), escuro)
	# Dois ecos deslocados por poucos pixels criam a separação cromática
	# curta do impacto sem exigir shader ou deixar o placar ilegível.
	if clarao > 0.18 and state == GameDef.State.MEASURING:
		var alvo := _alvo()
		var raio := 100.0 + (1.0 - clarao) * 120.0
		draw_arc(alvo + Vector2(-9.0, 0.0), raio, 0.0, TAU, 72, Color(Paleta.CIANO, clarao * 0.65), 7.0, true)
		draw_arc(alvo + Vector2(9.0, 0.0), raio, 0.0, TAU, 72, Color(Paleta.VERMELHO, clarao * 0.60), 7.0, true)

# ---------------------------------------------------------------- abertura
## A ABERTURA NÃO É UMA TELA SÓ.
##
## Uma máquina de fliperama parada não fica repetindo o mesmo cartaz: ela
## conta o jogo em capítulos, e é o rodízio que segura quem está passando
## no corredor por tempo suficiente para a pessoa decidir jogar. Três
## páginas alternando sozinhas — a marca, os melhores da casa e como
## jogar — e, fixos em todas, o convite e os números da máquina, porque
## esses dois não podem depender de a pessoa ter chegado na página certa.
const ABERTURA_PAGINAS := 4
const ABERTURA_SEGUNDOS := 7.0

## Página 2 — as cinco melhores marcas.
func _pagina_recordes(alpha: float) -> void:
	_texto_arcade("TOP 20 • MELHORES", 392.0, 62, Color(Paleta.CIANO, alpha), LARGURA_UTIL)
	if ranking.is_empty():
		_texto("AINDA NINGUÉM SOCOU ESTA MÁQUINA", 780.0, 32, Color(Paleta.TINTA_FRACA, alpha))
		_texto("O PRIMEIRO NOME DA LISTA PODE SER O SEU", 832.0, 24, Color(Paleta.TINTA_LEVE, alpha))
		return
	var page := int(state_time / 16.0) % 4
	for row in range(5):
		var i := page * 5 + row
		var y := 466.0 + row * 116.0
		var cor := _cor_da_posicao(i + 1)
		var linha := Rect2(MARGEM + 40.0, y, LARGURA_UTIL - 80.0, 98.0)
		var vazia := i >= ranking.size()
		_cartao(linha, Paleta.CARTAO if not vazia else Paleta.VAZIO, Paleta.CARTAO_BORDA, alpha, 2.0)
		# Tarja lateral colorida: identifica a posição sem pintar a linha.
		draw_rect(Rect2(linha.position, Vector2(9.0, linha.size.y)), Color(cor, alpha))
		var meio := linha.position.y + 64.0
		_texto("%dº" % (i + 1), meio, 34, Color(cor, alpha), HORIZONTAL_ALIGNMENT_CENTER, linha.position.x + 30.0, 90.0)
		if i < 3:
			Icones.trofeu(self, Vector2(linha.position.x + 168.0, meio - 11.0), 19.0, Color(cor, alpha))
		if vazia:
			_texto("—", meio, 34, Color(Paleta.TINTA_LEVE, alpha), HORIZONTAL_ALIGNMENT_RIGHT, linha.position.x, linha.size.x - 40.0)
		else:
			_draw_player_photo(Rect2(linha.position + Vector2(210.0, 11.0), Vector2(76.0, 76.0)), str(ranking[i].get("photo_path", "")), alpha)
			_texto("%04d" % RankingStore.score_at(ranking, i), meio, 44, Color(Paleta.TINTA, alpha), HORIZONTAL_ALIGNMENT_RIGHT, linha.position.x, linha.size.x - 40.0)
			_texto("PONTOS", meio, 18, Color(Paleta.TINTA_LEVE, alpha), HORIZONTAL_ALIGNMENT_RIGHT, linha.position.x, linha.size.x - 190.0)
	_texto("POSIÇÕES %02d–%02d" % [page * 5 + 1, page * 5 + 5], 1152.0, 26, Color(Paleta.CIANO, alpha))

## Página 3 — os três passos, do tamanho de quem lê de longe.
func _pagina_como_jogar(alpha: float) -> void:
	_texto_arcade("COMO JOGAR", 392.0, 62, Color(Paleta.CIANO, alpha), LARGURA_UTIL)
	var passos := [
		["ficha", "INSIRA A FICHA" if game_mode == "credit" else "MÁQUINA LIBERADA", Paleta.ROSA],
		["botao", "APERTE START", Paleta.VERDE],
		["alvo", "SOQUE O ALVO COM FORÇA", Paleta.VERMELHO],
	]
	for i in range(passos.size()):
		var y := 428.0 + i * 236.0
		var cor: Color = passos[i][2]
		var centro := Vector2(MARGEM + 110.0, y + 60.0)
		draw_circle(centro, 62.0, Paleta.tinta_clara(cor, 0.20), true, -1.0, true)
		draw_arc(centro, 62.0, 0.0, TAU, 60, Color(cor, 0.55 * alpha), 4.0)
		_icone(str(passos[i][0]), centro, 38.0, Color(Paleta.para_texto(cor), alpha))
		_texto(
			"%d." % (i + 1), centro.y - 4.0, 26, Color(cor, alpha),
			HORIZONTAL_ALIGNMENT_LEFT, MARGEM + 210.0, 80.0
		)
		# Alinhados à ESQUERDA e não centrados: três frases de comprimentos
		# diferentes, centradas cada uma na sua caixa, não formam uma
		# coluna — e é a coluna que faz a lista ser lida como três passos.
		var texto := str(passos[i][1])
		_texto(
			texto, centro.y + 14.0, _tamanho_que_cabe(texto, 44, LARGURA_UTIL - 340.0),
			Color(Paleta.TINTA, alpha), HORIZONTAL_ALIGNMENT_LEFT,
			MARGEM + 270.0, LARGURA_UTIL - 340.0
		)

# ---------------------------------------------------------------- partida
## Todos os momentos da partida compartilham o mesmo visor. O que muda é
## o que está escrito nele, a cor do anel e quanto do anel está aceso.
func _draw_partida() -> void:
	# O cabeçalho da rodada é o MESMO letreiro do cabeçalho da abertura,
	# no mesmo corpo: são a mesma máquina, e a pessoa não deve sentir que
	# trocou de programa ao apertar START.
	_letreiro_centrado("PUNCH CHALLENGE", 145.0, 32, Paleta.CREME)
	# A marca acompanha a rodada inteira, à direita e discreta — menos na
	# contagem, onde ela é desenhada ao lado do visor da foto.
	if state != GameDef.State.COUNTDOWN:
		_marca_lateral(1766.0, 0.70, 78.0)
	match state:
		GameDef.State.COUNTDOWN:
			_texto_arcade("FAÇA SUA POSE", 340.0, 72, Paleta.CIANO, LARGURA_UTIL)
			var rect := Rect2(180, 470, 720, 720)
			_cartao(Rect2(170, 460, 740, 740), Color("330c16"), Paleta.CIANO, 1.0, 4.0)
			# A MARCA DA CASA LOGO ABAIXO DO VISOR, à direita e grande o
			# bastante para se ler de pé na frente da máquina. Fora da
			# foto: dentro dela o carimbo some na miniatura do ranking e
			# atrapalha no retrato grande.
			_marca_lateral(1218.0)
			if pose_finished:
				# SEM FOTO, A CÂMERA CONTINUA À VISTA. Cair no boneco
				# desenhado com a webcam acesa na frente da pessoa é o
				# que dá a impressão de a câmera ter desligado justamente
				# na hora de fotografar.
				if result_photo_path.is_empty() and camera_service != null and camera_service.tem_imagem():
					_draw_texture_cover(camera_service.preview_texture(), rect, 1.0, camera_mirrored)
					draw_rect(rect, Color(Paleta.CIANO, 1.0), false, 3.0)
				else:
					_draw_player_photo(rect, result_photo_path, 1.0)
			elif camera_service != null and camera_service.tem_imagem():
				# `tem_imagem`, e não `available`: a segunda pergunta se a
				# imagem é DESTE instante, e um atraso de meio segundo na
				# ponte fazia a prévia voltar a ser o boneco com a webcam
				# acesa na frente da pessoa.
				_draw_texture_cover(camera_service.preview_texture(), rect, 1.0, camera_mirrored)
			else:
				_draw_avatar(rect, 1.0)
				# A CÂMERA PODE ESTAR SÓ ABRINDO. O boneco desenhado
				# sozinho diz "não há câmera"; com o anel girando por
				# cima ele diz "espera, estou chegando", que é a verdade
				# nos primeiros segundos de qualquer rodada.
				if camera_enabled:
					_carregando(rect.get_center() + Vector2(0.0, 210.0), 30.0, Paleta.CIANO)
			if aguardando_camera:
				# Enquanto a câmera sobe, a tela diz o que está esperando
				# — e o anel girando prova que a máquina não travou.
				_carregando(Vector2(540.0, 1400.0), 40.0, Paleta.CIANO)
				_rotulo(
					camera_service.estado_curto() if camera_service != null else "LIGANDO A CÂMERA…",
					1490.0, Paleta.CIANO
				)
			elif not pose_finished:
				_texto_arcade(str(clampi(int(ceil(countdown_left)), 1, 3)), 1400.0, 150, Color.WHITE, LARGURA_UTIL)
				_rotulo("OLHE PARA A CÂMERA", 1490.0, Paleta.AMBAR)
			else:
				# O MOTIVO DE VERDADE, e não "SEM CÂMERA" para tudo. A
				# mesma frase servia para câmera desligada na Central,
				# Python faltando, webcam ocupada e ponte ainda subindo —
				# e quem estava na frente da máquina não tinha como saber
				# qual das quatro era.
				var recado := "FOTO PRONTA"
				var cor_recado := Paleta.AMBAR
				if result_photo_path.is_empty():
					recado = camera_service.motivo_curto() if camera_service != null else "SEM CÂMERA"
					cor_recado = Paleta.VERMELHO
				_rotulo(recado, 1390.0, cor_recado)
				_texto_arcade("PREPARE O SOCO", 1480.0, 56, Color.WHITE, LARGURA_UTIL)
		GameDef.State.ARMED:
			_draw_espera_do_soco()
		GameDef.State.MEASURING, GameDef.State.RESULT:
			_draw_score_hero()

## A TELA QUE ESPERA O SOCO.
##
## Não há saco desenhado, não há barra de tempo e — desde a escala de
## quatro dígitos — não há mais CÍRCULO DE PLACAR aqui. O círculo é o
## objeto que revela a nota; mostrá-lo antes do golpe, mesmo vazio,
## promete um número que ainda não existe e ensina a pessoa a olhar para
## o lugar errado justamente quando ela deveria estar olhando para o saco
## de verdade.
##
## O que fica é um ALVO: anéis concêntricos respirando no ponto onde o
## soco aterrissa, com o farol mandando anéis para fora. Chamada, e não
## instrumento.
func _draw_espera_do_soco() -> void:
	_draw_farol(Paleta.AMBAR)
	var piscada := 0.78 + 0.22 * sin(animation_time * 4.4)
	_texto_arcade("SOQUE AGORA!", 1420.0, 96, Color(Color.WHITE, piscada), LARGURA_UTIL)
	_rotulo("ACERTE O ALVO COM TODA A FORÇA", 1488.0, Color.WHITE)
	_rotulo("RECORDE DA CASA  %04d" % _melhor(), 1556.0, Paleta.AMBAR)

	# O RELÓGIO SÓ APARECE NO FIM, e vem acompanhado da promessa.
	#
	# Nos primeiros setenta e cinco segundos não há relógio nenhum: a
	# máquina espera calada, que é o que se pediu. Só quando ela vai mesmo
	# desistir é que avisa — e avisa dizendo que a ficha volta, senão o
	# aviso vira ameaça.
	if espera_left <= GameDef.AVISO_DE_VOLTA:
		var segundos := maxi(0, int(ceil(espera_left)))
		_apoio("VOLTANDO EM %02d  •  O CRÉDITO É DEVOLVIDO" % segundos, 1786.0, Color.WHITE)

## O FAROL E O ALVO: anéis saindo do ponto do soco, em batidas.
##
## Três anéis defasados, sempre no mesmo compasso, e o alvo respirando no
## meio. Tudo se move para FORA — na direção de quem está olhando,
## chamando o punho. Anéis entrando leriam como contagem regressiva, que
## é exatamente o que esta tela deixou de ter.
func _draw_farol(cor: Color) -> void:
	var centro := ALVO_DO_SOCO
	var compasso := 1.15
	for i in range(3):
		var fase := fmod(animation_time / compasso + float(i) / 3.0, 1.0)
		var raio := lerpf(330.0, 620.0, ease(fase, 0.45))
		draw_arc(centro, raio, 0.0, TAU, 96, Color(cor, (1.0 - fase) * 0.55), 10.0, true)
	var respiro := 0.5 + 0.5 * sin(animation_time * 2.2)
	Icones.alvo(self, centro, lerpf(268.0, 288.0, respiro), cor)
	# Cantos de mira em volta do alvo: dizem "é AQUI" sem escrever nada.
	var recuo := lerpf(330.0, 348.0, respiro)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var canto := centro + Vector2(sx * recuo, sy * recuo)
			draw_line(canto, canto - Vector2(sx * 70.0, 0.0), Color(cor, 0.85), 8.0, true)
			draw_line(canto, canto - Vector2(0.0, sy * 70.0), Color(cor, 0.85), 8.0, true)

## A ABERTURA GIRA EM TRÊS CAPÍTULOS.
##
## Uma máquina de fliperama parada não fica repetindo o mesmo cartaz: ela
## conta o jogo em partes, e é o rodízio que segura quem passa no
## corredor por tempo suficiente para decidir jogar. A marca, os melhores
## da casa e como jogar — e, FIXOS nos três, o convite e os créditos,
## porque um botão que muda de lugar a cada oito segundos é um botão que
## ninguém acha.
const ABERTURA_CAPITULOS := 3
const ABERTURA_DURACAO := 8.0

## O LAÇO DE ATRAÇÃO: a apresentação volta sozinha.
##
## Uma máquina de salão passa a maior parte da noite sem ninguém na
## frente, e o que ela mostra nessas horas é o que trás gente. O rodízio
## de capítulos (marca, recordes, como jogar) prende quem já parou; quem
## está passando a dez metros só olha se alguma coisa MEXER — e a cut
## scene do soco é o que a máquina tem de mais chamativo.
##
## Um minuto e vinte é o intervalo: curto o bastante para pegar quem
## passa duas vezes pelo corredor, longo o bastante para os três
## capítulos rodarem inteiros antes de a entrada recomeçar.
const ATRACAO_INTERVALO := 80.0

func _laco_de_atracao(delta: float) -> void:
	# Só na tela de espera, e nunca com a Central aberta: reiniciar a
	# entrada por baixo do técnico que está configurando é o tipo de
	# surpresa que faz ele perder o que estava fazendo.
	if state != GameDef.State.IDLE or intro_active or central_aberta or calib_ativo:
		atracao_relogio = 0.0
		return
	atracao_relogio += delta
	if atracao_relogio < ATRACAO_INTERVALO:
		return
	atracao_relogio = 0.0
	# A ENTRADA DE NOVO, do primeiro quadro: o selo da casa, os facões de
	# luz, o soco chegando de lado e a montagem do letreiro.
	intro_active = true
	intro_time = 0.0
	abertura_chegada = 1.0
	fx.limpar()
	sons.music(-18.0)

func _draw_show_idle() -> void:
	var chegada := ease(abertura_chegada, 0.4)
	_marca_da_casa(146.0, 132.0, chegada)
	var capitulo := int(state_time / ABERTURA_DURACAO) % ABERTURA_CAPITULOS
	# Cada capítulo entra com o seu próprio esmaecer; sem isso só o
	# primeiro teria entrada e os outros dariam um salto seco.
	var entrada := ease(clampf(fmod(state_time, ABERTURA_DURACAO) / 0.5, 0.0, 1.0), 0.35)
	match capitulo:
		1:
			_pagina_recordes(entrada)
		2:
			_pagina_como_jogar(entrada)
		_:
			_capitulo_da_marca(entrada)
	_pontos_do_capitulo(capitulo, chegada)
	var pulse := 0.8 + 0.2 * sin(animation_time * 2.6)
	_cartao(Rect2(140, 1560, 800, 112), Color("d9122d"), Color(Paleta.AMBAR, pulse), chegada, 3.0)
	_texto("PRESSIONE START", 1635.0, 46, Color(Color.WHITE, chegada))
	# O LUGAR DO CRÉDITO PISCA quando alguém aperta START sem saldo.
	var cor_credito := Color(Paleta.CIANO, chegada)
	if aviso_de_credito >= 0.0:
		var bate := 0.5 + 0.5 * sin(aviso_de_credito * 16.0)
		cor_credito = Color(Paleta.VERMELHO.lerp(Paleta.AMBAR, bate), chegada)
		_cartao(
			Rect2(300, 1700, 480, 62), Color(Paleta.VERMELHO, 0.20 * bate),
			Color(Paleta.AMBAR, bate), chegada, 3.0
		)
	_texto(
		"JOGO LIVRE" if game_mode == "free" else "CRÉDITOS  %02d" % credits,
		1740.0, 26, cor_credito
	)
	# CARIMBO DA BUILD. Discreto, mas na tela que fica ligada o dia
	# inteiro: é ele que responde "atualizei e não mudou nada" sem
	# ninguém precisar abrir terminal.
	_texto(Versao.curta(), 1876.0, 15, Color(1, 1, 1, 0.55 * chegada))

func _capitulo_da_marca(alpha: float) -> void:
	ArcadeStage.emblem(self, Vector2(540, 560 + sin(animation_time * 1.4) * 8), 440.0, alpha)
	# O NOME É DESENHADO PELO NÓ DO SHADER, e não aqui. Ele continua no
	# mesmo lugar, no mesmo corpo e com a mesma entrada esmaecida — o que
	# muda é quem passa a tinta, porque só um nó pode carregar material.
	_nome_do_jogo(alpha)
	_texto("QUAL É A SUA FORÇA?", 1120.0, 32, Color(Color.WHITE, alpha))
	_texto("RECORDE DA CASA", 1270.0, 24, Color(Color("d8b6a6"), alpha))
	_texto("%04d" % _melhor(), 1400.0, 98, Color(Paleta.AMBAR, alpha))

## ENTREGA O NOME AO NÓ QUE TEM O SHADER.
##
## O reflexo que corre dentro das letras precisa de um material, material
## é propriedade do nó, e o resto da tela é desenhado à mão num Control
## só — pôr o shader ali aplicaria o brilho ao fundo, aos cartões e ao
## placar. Então o nome mora num nó próprio, e esta função é a ponte:
## a tela continua mandando quando, onde e com que opacidade.
func _nome_do_jogo(alpha: float) -> void:
	# O NÓ FICA ACIMA DO DESENHO PRINCIPAL — é o que faz o reflexo passar
	# por cima do letreiro em vez de ficar embaixo do fundo. O preço é
	# que a Central, a calibração e a cortina de transição, desenhadas
	# pelo nó de baixo, NÃO cobrem o nome: sem esta guarda, o
	# "PUNCH CHALLENGE" aparecia atravessado no meio da Central Técnica.
	if alpha <= 0.01 or central_aberta or calib_ativo or transicao >= 0.0:
		letreiro_do_nome.esconder()
		return
	letreiro_do_nome.mostrar(
		[
			{"texto": "PUNCH", "x": 540.0, "y": 910.0, "tamanho": 144, "cor": Color(Color.WHITE, alpha)},
			{"texto": "CHALLENGE", "x": 540.0, "y": 1010.0, "tamanho": 80, "cor": Color(Paleta.AMBAR, alpha)},
		],
		# A faixa atravessa a LARGURA DO NOME, e não a da tela: medida na
		# tela, o reflexo levaria o mesmo tempo cruzando as letras e o
		# vazio dos dois lados, e a passagem pareceria travar no meio.
		190.0, 700.0
	)

## Quantos capítulos existem e em qual estamos. Sem isso o rodízio parece
## a tela trocando sozinha por defeito.
func _pontos_do_capitulo(capitulo: int, alpha := 1.0) -> void:
	var largura := float(ABERTURA_CAPITULOS) * 30.0
	for i in range(ABERTURA_CAPITULOS):
		var atual := i == capitulo
		var centro := Vector2(540.0 - largura * 0.5 + 15.0 + i * 30.0, 1500.0)
		var cor: Color = Paleta.AMBAR if atual else Color("6d2835")
		draw_circle(centro, 8.0 if atual else 5.0, Color(cor, alpha), true, -1.0, true)

func _draw_score_hero() -> void:
	var center := Vector2(540, 930)
	var measuring := state == GameDef.State.MEASURING
	# O ANEL MEDE A FORÇA, NÃO O RELÓGIO.
	#
	# Ele enchia com `result_time / CONTAGEM_DURACAO`, ou seja, com o
	# tempo da animação: um soco de 120 pontos fechava o anel inteiro
	# igualzinho a um de 961, porque os dois levavam os mesmos dois
	# segundos para contar. A pessoa batia fraco e via a barra encostar
	# no fim — e aí nada na tela combinava com o que ela tinha feito.
	# Ligado à pontuação, o anel vira o retrato do golpe: fraco fecha um
	# pedaço, nocaute fecha quase tudo. E continua animando, porque
	# `displayed_score` é o número subindo.
	var progress := 0.0 if measuring else clampf(displayed_score / float(GameDef.SCORE_MAX), 0.0, 1.0)
	# A cor também é a da faixa conquistada, e não uma só para todo mundo:
	# o anel de um golpe fraco não pode ser igual ao de um nocaute.
	var color := Paleta.CIANO
	if verdict_time >= 0.0:
		color = GameDef.classificar(result_score)["cor_faixa"] as Color
	_draw_campo_de_forca(center, color, progress, measuring)
	_draw_colunas_de_forca(color, progress)
	# O HALO DO ANEL, EM TRÊS PASSADAS E NÃO EM DOZE.
	#
	# Aqui havia doze anéis de 192 segmentos cada, com alfa 0,02 — três
	# níveis de tinta em duzentos e cinquenta e cinco, ou seja, cada um
	# praticamente invisível sozinho. Somados custavam TREZE MIL
	# triângulos por quadro, que era sessenta por cento de todo o desenho
	# desta tela. Três anéis mais largos, com o alfa somado, dão o mesmo
	# brilho por um doze avos do preço.
	#
	# E 64 segmentos bastam: num raio de 340 px, a flecha do arco de 64
	# lados é de quatro décimos de pixel. Os 192 desenhavam três vezes
	# mais geometria para descrever a mesma circunferência.
	for i in range(3):
		draw_arc(center, 337.0 + float(i) * 11.0, 0, TAU, 64, Color(color, 0.075), 13.0, true)
	draw_circle(center, 326.0, Color("250911"), true, -1.0, true)
	draw_arc(center, 327, 0, TAU, 96, Color("6d2835"), 4.0, true)
	for i in range(60):
		var angle := float(i) / 60.0 * TAU - PI * 0.5
		var lit := float(i) / 60.0 <= progress
		draw_arc(center, 347, angle, angle + 0.065, 5, color if lit else Color("57212c"), 14.0, true)
	draw_arc(center, 302, animation_time * 0.5, animation_time * 0.5 + 1.2, 64, Color(color, 0.55), 2.0, true)
	_rotulo("IMPACTO" if measuring else ("SUA PONTUAÇÃO" if verdict_time >= 0.0 else "CALCULANDO"), 785.0, color)
	_placar(
		"– – – –" if measuring else "%04d" % int(round(displayed_score)),
		center + Vector2(0.0, 20.0), color if measuring else Color.WHITE
	)
	if verdict_time >= 0.0:
		_rotulo("PONTOS", 1110.0, color)
		# A VELOCIDADE MEDIDA, ao lado dos pontos. Os pontos são uma nota
		# que a máquina inventou a partir de uma curva ajustável; a
		# velocidade é o que o sensor de fato viu. Quem duvida do placar
		# ("essa máquina está roubando") tem aqui o número cru.
		_apoio("%.1f m/s no sensor" % result_speed, 1330.0, Paleta.TINTA_FRACA)
		# O NOME DO NÍVEL VEM ANTES DA COLOCAÇÃO. A pessoa quer saber o
		# que ela fez — "NOCAUTE" — e só depois onde isso a coloca. A
		# ordem inversa transformava o veredito numa tabela.
		_texto_arcade(ScoreTier.nome_de(result_score), 1440.0, 84, color, LARGURA_UTIL)
		if posicao_no_ranking > 0:
			_rotulo("%dº LUGAR NO TOP 20" % posicao_no_ranking, 1520.0, Paleta.AMBAR)

## O CARREGANDO: UM ANEL QUE GIRA E UMA FRASE DO QUE ESTÁ ACONTECENDO.
##
## Toda espera desta máquina era silenciosa. O diagnóstico da câmera podia
## levar dois minutos instalando o OpenCV e a tela ficava idêntica à de
## antes de apertar; a ponte podia estar subindo enquanto a tela da pose
## já mostrava o boneco desenhado, como se não houvesse câmera nenhuma.
## Espera sem sinal é indistinguível de defeito — e quem está na frente
## do gabinete conclui, sempre, que apertou e não aconteceu nada.
##
## O anel não é enfeite: ele GIRA, e é o giro que prova que o programa
## está vivo. Uma barra parada em 40% diria menos do que este anel.
func _carregando(centro: Vector2, raio: float, cor: Color, texto := "") -> void:
	draw_arc(centro, raio, 0.0, TAU, 48, Color(cor, 0.16), 5.0, true)
	var comeco := animation_time * 3.4
	draw_arc(centro, raio, comeco, comeco + 1.5, 24, cor, 5.0, true)
	# Um segundo arco, mais lento e no sentido contrário: com um só, em
	# giro constante, o olho perde a referência e o anel parece parado.
	draw_arc(centro, raio * 0.62, -comeco * 0.7, -comeco * 0.7 + 0.9, 18, Color(cor, 0.55), 4.0, true)
	if not texto.is_empty():
		_texto(texto, centro.y + raio + 40.0, 18, cor, HORIZONTAL_ALIGNMENT_CENTER, centro.x - 300.0, 600.0)

## O PLACAR: QUATRO ALGARISMOS, E NADA DISPUTANDO COM ELES.
##
## Aqui havia um visor de sete segmentos desenhado traço a traço. A ideia
## era boa no papel — num fliperama o placar é um painel de LED atrás de
## um vidro, e o que denuncia isso é o segmento APAGADO atrás do número.
## Na tela ela não fecha: sete traços com catorze junções em bisel, mais
## os apagados por baixo, produzem uma grade, e a três metros a grade
## ganha do algarismo. Foram três desenhos diferentes e os três leram
## como grade.
##
## Então o placar é tipográfico, na letra do cartaz — a mesma do
## logotipo, a mesma do PUNCH CHALLENGE. Um número é uma forma que a
## pessoa reconhece antes de ler, e é isso que um placar precisa ser.
## O tratamento é o de fliperama, em quatro passadas:
##
##   1. um halo largo na cor da faixa, que é o vidro espalhando a luz;
##   2. um contorno grosso quase preto, que segura o número sobre o anel
##      aceso e sobre o clarão do soco;
##   3. uma cópia clara alguns pixels acima, que vira o brilho do topo;
##   4. o número.
##
## `tabular` importa: sem ele, cada algarismo tem a sua largura e o
## placar DANÇA de lado enquanto sobe de 0000 a 9999.
const PLACAR_CORPO := 190

func _placar(texto: String, centro: Vector2, cor: Color) -> void:
	var medida := fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, PLACAR_CORPO)
	var pos := Vector2(centro.x - medida.x * 0.5, centro.y + PLACAR_CORPO * 0.36)
	for i in range(3):
		draw_string_outline(
			fonte, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, PLACAR_CORPO,
			int(PLACAR_CORPO * (0.16 + float(i) * 0.09)), Color(cor, 0.10)
		)
	draw_string_outline(
		fonte, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, PLACAR_CORPO,
		int(PLACAR_CORPO * 0.085), Color(Paleta.CONTORNO, 0.95)
	)
	draw_string(
		fonte, pos - Vector2(0.0, PLACAR_CORPO * 0.045), texto,
		HORIZONTAL_ALIGNMENT_LEFT, -1, PLACAR_CORPO, cor.lightened(0.5)
	)
	draw_string(fonte, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, PLACAR_CORPO, cor)

## O VAZIO ATRÁS DO PLACAR ERA O MAIOR PEDAÇO DA TELA.
##
## O medalhão ocupa o meio e o painel é alto: sobrava um retângulo preto
## de mais de mil pixels em volta, justamente nos dois segundos em que
## todo mundo está olhando. Agora o placar irradia — e irradia NA MEDIDA
## DA PONTUAÇÃO, para que a tela inteira, e não só o número, diga se o
## soco foi forte.
func _draw_campo_de_forca(centro: Vector2, cor: Color, progresso: float, no_impacto: bool) -> void:
	# No meio segundo do impacto ainda não há pontuação nenhuma para
	# mostrar, então quem manda é o próprio golpe: começa no talo e
	# desinfla enquanto a máquina "calcula".
	var forca := progresso
	if no_impacto:
		forca = 1.0 - clampf(state_time / GameDef.IMPACTO_DURACAO, 0.0, 1.0)
	# O CAMPO DE FORÇA, EM TRÊS DISCOS E NÃO EM SETE.
	#
	# Cada um destes discos tem raio maior que meia tela: sete deles são
	# sete telas inteiras pintadas por quadro, com alfa 0,013 — tinta que
	# ninguém enxerga isolada. Não custa triângulo, custa TAXA DE
	# PREENCHIMENTO, que é o que falta primeiro num PC de gabinete com
	# vídeo integrado. Três discos com o alfa somado dão o mesmo halo.
	for i in range(3):
		draw_circle(centro, 392.0 + float(i) * 150.0, Color(cor, 0.030 * forca), true, -1.0, true)
	for i in range(36):
		var ang := float(i) * TAU / 36.0 + animation_time * 0.22
		var onda := 0.5 + 0.5 * sin(float(i) * 1.7 - animation_time * 4.0)
		var perto := 372.0
		var longe := perto + lerpf(24.0, 200.0, forca * onda)
		draw_line(
			centro + Vector2.from_angle(ang) * perto,
			centro + Vector2.from_angle(ang) * longe,
			Color(cor, 0.08 + 0.34 * forca * onda), 6.0, true
		)

## AS DUAS COLUNAS, uma de cada lado do painel.
##
## São a mesma pontuação lida de outro jeito, e existem porque o número
## no meio é redondo e o olho não compara redondo com redondo. Coluna
## cheia contra coluna pela metade é a diferença entre dois socos vista
## de longe, sem ler algarismo nenhum.
func _draw_colunas_de_forca(cor: Color, progresso: float) -> void:
	var degraus := 22
	for lado in [0.0, 1.0]:
		var x := lerpf(92.0, 944.0, lado)
		for i in range(degraus):
			var fatia := float(i) / float(degraus)
			var caixa := Rect2(x, 1512.0 - float(i) * 44.0, 44.0, 26.0)
			if fatia < progresso:
				draw_rect(caixa, cor)
				draw_rect(caixa.grow(3.0), Color(cor, 0.18))
			else:
				draw_rect(caixa, Color("3a141d"))

## Ouro, prata e bronze nos três primeiros; azul da casa nos demais. É a
## convenção que todo mundo já lê sem legenda.
func _cor_da_posicao(posicao: int) -> Color:
	match posicao:
		1:
			return Paleta.AMBAR
		2:
			return Color("8fa3bd")
		3:
			return Color("c1783a")
	return Paleta.CIANO

## Resultado encerra em uma cerimônia: a lista se move até a colocação
## conquistada, sem reduzir vinte fotos a miniaturas ilegíveis.
## A ENTRADA NO RANKING, EM QUATRO ATOS.
##
## Antes era um movimento só: a tabela chegava deslizando e, no meio
## dela, uma linha vinha destacada. Quem entrou no Top 20 descobria isso
## lendo — e ler não é comemorar. O momento pelo qual a pessoa jogou
## passava sem acontecer.
##
## Agora há uma ORDEM, e cada ato faz uma coisa só:
##
##   1. O ANÚNCIO. A tela inteira para no aviso. Nada de tabela ainda:
##      primeiro a notícia, depois o contexto.
##   2. A TABELA CHEGA. As linhas entram e a lista rola até a vizinhança
##      da posição conquistada.
##   3. A LINHA ASSENTA. O cartão de quem jogou desce no lugar dele e
##      bate — é o instante em que o nome ENTRA na lista.
##   4. O CONFETE. Depois, e não antes: confete durante o movimento vira
##      sujeira por cima da informação; depois dele, vira festa.
##
## Quem NÃO entrou no Top 20 pula os atos 1, 3 e 4 e vai direto à tabela.
## Comemorar o que não aconteceu é o jeito mais rápido de a máquina
## perder a credibilidade.
## SEM PRESSA. Os tempos eram 0,90 / 0,85 / 0,55 — dois segundos e pouco
## para anunciar, montar a tabela e assentar a linha. Cabia, mas passava
## rápido demais para ser vivido: quem entrou no Top 20 mal via acontecer.
## Um segundo a mais em cada ato não atrasa a fila (o veredito fica doze
## segundos na tela de qualquer jeito) e é a diferença entre ver e ler.
const ATO_ANUNCIO := 1.45
const ATO_TABELA := 1.20
const ATO_ASSENTA := 0.80

func _tempo_do_ranking() -> float:
	return maxf(0.0, verdict_time - 2.5)

func _draw_ranking_reveal() -> void:
	var t := _tempo_do_ranking()
	var entrou := posicao_no_ranking > 0
	# Sem entrada no ranking não há anúncio nem assentamento: a tabela é
	# a única coisa que essa pessoa tem para ver.
	var anuncio := ATO_ANUNCIO if entrou else 0.0
	if entrou and t < anuncio:
		_ranking_anuncio(t / anuncio)
		return

	var chegada := clampf((t - anuncio) / ATO_TABELA, 0.0, 1.0)
	var eased := chegada * chegada * (3.0 - 2.0 * chegada)
	var assenta := clampf((t - anuncio - ATO_TABELA) / ATO_ASSENTA, 0.0, 1.0)

	_texto_arcade("TOP 20", 220.0, 110, Paleta.CIANO, LARGURA_UTIL)
	var titulo := "%dº LUGAR • VOCÊ ENTROU!" % posicao_no_ranking if entrou else "TENTE SUPERAR ESSAS MARCAS"
	_texto_cabendo(titulo, 312.0, 38, Paleta.AMBAR, LARGURA_UTIL)

	var position_index := maxi(posicao_no_ranking - 1, 0)
	var target := clampi(position_index - 2, 0, 15)
	var offset := float(target) * 164.0 * eased
	# AS VINTE VAGAS, e não só as ocupadas. Numa máquina nova a lista tem
	# uma linha e dezenove buracos; desenhando só o que existe, a tela
	# vira um cartão solto num vazio preto. Desenhando a vaga aberta, o
	# mesmo vazio passa a dizer "sobrou lugar para você".
	for i in range(RANKING_TAMANHO):
		var y := 430.0 + float(i) * 164.0 - offset
		var vazia := i >= ranking.size()
		var selected := posicao_no_ranking == i + 1
		# A LINHA DE QUEM JOGOU CAI DE CIMA, mas de perto: 520 px a
		# levavam para cima do cabeçalho, e a tabela ficava com o "03"
		# flutuando acima do "01". Duzentos e sessenta é o bastante para
		# a queda ser vista sem a linha sair da lista.
		var descida := 0.0
		if selected:
			# UMA ALTURA DE LINHA, e não mais. A vaga dela já está aberta
			# na lista — as outras linhas nunca ocuparam o lugar. Caindo
			# de 260 px ela cruzava DUAS linhas no caminho, e cruzar
			# linha lê como defeito de desenho, não como chegada. De 150
			# ela desce da vizinhança do próprio lugar.
			descida = (1.0 - _passo_com_batida(assenta)) * 150.0
			y -= descida
		# O RECORTE VEM DEPOIS DA QUEDA, e não antes: era por conferir a
		# altura antes de aplicar o deslocamento que a linha escapava da
		# janela da lista e ia parar em cima do título.
		if y < 380.0 or y > 1150.0:
			continue
		var color := Paleta.AMBAR if selected else _cor_da_posicao(i + 1)
		# AS LINHAS ENTRAM PELA ESQUERDA, nunca pela direita.
		#
		# O deslocamento era positivo: cada linha começava até 200 px à
		# direita do lugar dela e, como a largura não mudava, a linha
		# inteira passava dos 1080 px da tela — a pontuação, que fica na
		# ponta direita, ficava cortada durante toda a entrada. Negativo,
		# a linha entra de fora da tela e assenta; nada some.
		var shift := -(1.0 - eased) * (80.0 + float(i % 5) * 30.0)
		if selected:
			# Ela não entra pela esquerda com as outras: cai de cima e
			# bate. É esse atraso que faz a tabela parecer ABRIR ESPAÇO
			# para ela em vez de já vir pronta.
			shift = 0.0
		var card := Rect2(90.0 + shift, y, 900.0, 144.0)
		if vazia:
			_cartao(card, Color("1c060c"), Color("4a1420"), 1.0, 1.5)
			_texto("%02d" % (i + 1), y + 91.0, 45, Color("4a1420"), HORIZONTAL_ALIGNMENT_LEFT, card.position.x + 22.0)
			_texto("VAGA ABERTA", y + 91.0, 30, Color("6d2835"), HORIZONTAL_ALIGNMENT_LEFT, card.position.x + 270.0)
			continue
		if selected and assenta < 1.0:
			# CHEGA APARECENDO, e não atravessando. Com opacidade cheia a
			# linha passa por cima das vizinhas no caminho e o olho lê um
			# cartão solto deslizando sobre a tabela; entrando de leve,
			# ela se materializa no lugar dela.
			var tinta := clampf(assenta * 1.8, 0.0, 1.0)
			if tinta < 1.0:
				_cartao(card, Color("b21029", tinta), Color(color, tinta), 1.0, 4.0)
				_texto("%02d" % (i + 1), y + 91.0, 45, Color(color, tinta), HORIZONTAL_ALIGNMENT_LEFT, card.position.x + 22.0)
				_texto("VOCÊ", y + 64.0, 26, Color(color, tinta), HORIZONTAL_ALIGNMENT_LEFT, card.position.x + 270.0)
				_texto("%04d" % RankingStore.score_at(ranking, i), y + 106.0, 62, Color(Paleta.TINTA, tinta), HORIZONTAL_ALIGNMENT_RIGHT, card.position.x, card.size.x - 35.0)
				continue
			# No quadro em que ela assenta, um halo curto marca a batida.
			for i2 in range(3):
				var atras := card.grow(6.0 + float(i2) * 10.0)
				_cartao(atras, Color(Paleta.AMBAR, 0.10 - float(i2) * 0.03), Color(Paleta.AMBAR, 0.0), 1.0, 6.0)
		_cartao(card, Color("b21029") if selected else Color("300b16"), color, 1.0, 4.0 if selected else 1.5)
		_draw_player_photo(Rect2(card.position + Vector2(124, 12), Vector2(120, 120)), str(ranking[i].get("photo_path", "")), 1.0)
		_texto("%02d" % (i + 1), y + 91.0, 45, color, HORIZONTAL_ALIGNMENT_LEFT, card.position.x + 22.0)
		_texto("VOCÊ" if selected else "JOGADOR", y + 64.0, 26, color, HORIZONTAL_ALIGNMENT_LEFT, card.position.x + 270.0)
		_texto("%04d" % RankingStore.score_at(ranking, i), y + 106.0, 62, Paleta.TINTA, HORIZONTAL_ALIGNMENT_RIGHT, card.position.x, card.size.x - 35.0)
	_rotulo("SEU SOCO", 1400.0, Paleta.TINTA_FRACA)
	_texto_arcade("%04d" % result_score, 1520.0, 100, Paleta.TINTA, LARGURA_UTIL)
	_rotulo("START • JOGAR NOVAMENTE", 1706.0, Paleta.AMBAR)
	# NO RANKING ELA É GRANDE. Esta é a tela que o pessoal fotografa com
	# o celular para mandar no grupo — é a que mais sai do salão, e a
	# única em que a marca da casa vale um lugar de destaque.
	_marca_lateral(1770.0, 0.95, 104.0)

## Chegada com batida: passa do ponto e volta. É o que faz a linha
## PARECER ter peso ao cair no lugar, em vez de deslizar até parar.
func _passo_com_batida(t: float) -> float:
	if t >= 1.0:
		return 1.0
	var p := t - 1.0
	return p * p * ((2.4 + 1.0) * p + 2.4) + 1.0

## ATO 1 — O ANÚNCIO, sozinho na tela.
##
## Um selo que cresce batendo, o número da posição dentro dele e nada
## mais. A tabela vem depois: notícia primeiro, contexto depois. Um
## anúncio dividindo a tela com vinte linhas de tabela não é um anúncio.
func _ranking_anuncio(t: float) -> void:
	var centro := Vector2(540.0, 820.0)
	var abre := clampf(t * 2.2, 0.0, 1.0)
	var escala := _passo_com_batida(abre)
	var raio := 300.0 * escala

	# Raios de luz saindo do selo, girando devagar.
	for i in range(18):
		var ang := float(i) * TAU / 18.0 + animation_time * 0.5
		var perto := raio * 1.12
		draw_line(
			centro + Vector2.from_angle(ang) * perto,
			centro + Vector2.from_angle(ang) * (perto + lerpf(30.0, 160.0, abre)),
			Color(Paleta.AMBAR, 0.30 * abre), 7.0, true
		)
	draw_circle(centro, raio, Color(Paleta.VERMELHO, 0.9), true, -1.0, true)
	draw_arc(centro, raio, 0.0, TAU, 72, Paleta.AMBAR, 9.0, true)
	draw_arc(centro, raio * 0.86, 0.0, TAU, 64, Color(Paleta.CREME, 0.45), 3.0, true)

	Icones.estrela(self, centro + Vector2(0.0, -raio * 0.44), raio * 0.20, Paleta.AMBAR)
	_texto_arcade("VOCÊ ENTROU", centro.y - raio * 0.02, 74, Paleta.CREME, 620.0, 230.0)
	_texto_arcade("NO TOP 20", centro.y + raio * 0.24, 62, Paleta.AMBAR, 620.0, 230.0)
	# O NÚMERO DA POSIÇÃO É A INFORMAÇÃO, e por isso ele é o maior
	# elemento do selo — não a frase.
	_texto_arcade("%dº" % posicao_no_ranking, centro.y + raio * 0.86, 132, Paleta.CREME, LARGURA_UTIL)

# ---------------------------------------------------------------- central
const CENTRAL_FUNDO := Color("2b0a13")

func _draw_central() -> void:
	var caixa := Rect2(40, 96, 1000, 1790)
	_placa(caixa, 22.0, Paleta.CARTAO_BORDA)
	_placa(caixa.grow(-5.0), 19.0, CENTRAL_FUNDO)

	# ---- O MIOLO, deslocado pela rolagem.
	#
	# O Godot não recorta o que um `_draw` desenha, então a página inteira
	# é desenhada e as duas faixas — cabeçalho e rodapé — são REPINTADAS
	# por cima logo depois. O efeito é o de uma janela com rolagem, sem
	# precisar de um SubViewport só para isso.
	central_fundo = 0.0
	draw_set_transform(_deslocamento - Vector2(0.0, central_rolagem), 0.0, Vector2.ONE)
	match central_pagina:
		1:
			_central_golpe()
		2:
			_central_camera()
		3:
			_central_dados()
		_:
			_central_operacao()
	draw_set_transform(_deslocamento, 0.0, Vector2.ONE)

	# ---- As faixas paradas, cobrindo o que a página passou por baixo.
	draw_rect(Rect2(45, 101, 990, CENTRAL_TOPO - 101.0), CENTRAL_FUNDO)
	draw_rect(Rect2(45, CENTRAL_BASE, 990, 1881.0 - CENTRAL_BASE), CENTRAL_FUNDO)
	_letreiro("CENTRAL TÉCNICA", Vector2(110.0, 204.0), 44, Paleta.CREME)
	_texto("Configuração, diagnóstico e calibração", 240.0, 18, Paleta.TINTA_FRACA, HORIZONTAL_ALIGNMENT_LEFT, 110.0)
	_botao(BOTOES_SIMPLES["fechar"], "×", false, Paleta.VERMELHO, 32)
	_abas_da_central()
	_barra_de_rolagem()

	_botao(BOTOES_SIMPLES["padroes"], "RESTAURAR PADRÕES", false, Paleta.AMBAR, 19)
	_botao(BOTOES_SIMPLES["salvar"], "SALVAR E FECHAR", true, Paleta.VERDE, 21)
	# Uma linha só: entre a última fileira de botões e a borda do painel
	# sobram poucos pixels, e duas linhas aí se atropelam. O carimbo da
	# build entra junto porque quem abre a Central é justamente quem
	# acabou de instalar a atualização e precisa confirmar que pegou.
	_texto(
		"%s     Tecla T: golpe de teste  •  Roda/setas: rola a página" % Versao.curta(),
		1872.0, 14, Paleta.TINTA_LEVE
	)

## A BARRA DE ROLAGEM, à direita do miolo.
##
## Ela não é enfeite: sem ela ninguém sabe que a página continua abaixo
## do que está à vista, e a informação que sobrou embaixo é exatamente a
## que faz falta — o diagnóstico da câmera, o saldo, as ações do
## firmware. Some sozinha quando a página cabe inteira.
func _barra_de_rolagem() -> void:
	var maxima := _rolagem_maxima()
	if maxima <= 1.0:
		return
	var trilho := Rect2(1014, CENTRAL_TOPO + 6.0, 8, CENTRAL_JANELA - 12.0)
	draw_rect(trilho, Color(Paleta.CREME, 0.10))
	var proporcao := CENTRAL_JANELA / (CENTRAL_JANELA + maxima)
	var altura := maxf(60.0, trilho.size.y * proporcao)
	var topo := trilho.position.y + (trilho.size.y - altura) * (central_rolagem / maxima)
	draw_rect(Rect2(trilho.position.x, topo, trilho.size.x, altura), Color(Paleta.AMBAR, 0.85))

func _abas_da_central() -> void:
	for i in range(PAGINAS.size()):
		var r := Rect2(
			ABA_RECT.position + Vector2(float(i) * ABA_LARGURA, 0.0),
			Vector2(ABA_LARGURA - 6.0, ABA_RECT.size.y)
		)
		var atual := i == central_pagina
		_cartao(r, Paleta.AMBAR if atual else Color("330c16"), Paleta.CARTAO_BORDA, 1.0, 2.0)
		_texto(
			str(PAGINAS[i]), r.position.y + 40.0, 20,
			Color("2b0a13") if atual else Paleta.TINTA_FRACA,
			HORIZONTAL_ALIGNMENT_CENTER, r.position.x, r.size.x
		)

# ---------------------------------------------------------- OPERAÇÃO
func _central_operacao() -> void:
	_secao(Rect2(80, 350, 920, 138), "MODO DE OPERAÇÃO", Paleta.ROSA)
	_botao(BOTOES_SIMPLES["modo_livre"], "LIVRE", game_mode == "free", Paleta.CIANO, 22)
	_botao(BOTOES_SIMPLES["modo_ficha"], "1 FICHA", game_mode == "credit", Paleta.ROSA, 22)

	# ---- os dois botões físicos do gabinete
	_secao(Rect2(80, 504, 920, 400), "BOTÕES DO GABINETE (ZERO DELAY)", Paleta.CIANO)
	_texto(
		"A placa aparece como controle USB e o índice muda de porta para porta. Mapeie aqui.",
		578.0, 15, Paleta.TINTA_FRACA
	)
	_botao(
		BOTOES_SIMPLES["mapear_start"],
		"AGUARDANDO START" if mapeando == "start" else "MAPEAR START",
		mapeando == "start", Paleta.VERDE, 19
	)
	_botao(
		BOTOES_SIMPLES["mapear_credito"],
		"AGUARDANDO CRÉDITO" if mapeando == "credito" else "MAPEAR CRÉDITO",
		mapeando == "credito", Paleta.AMBAR, 19
	)
	_ficha_do_botao(botao_start, "START", Rect2(110, 706, 400, 150), contador_start)
	_ficha_do_botao(botao_credito, "CRÉDITO", Rect2(570, 706, 400, 150), contador_credito)

	_secao(Rect2(80, 1170, 920, 130), "SALDO", Paleta.AMBAR)
	_texto(
		"Créditos %02d  •  partidas contadas %d  •  modo %s" % [
			credits, plays, "livre" if game_mode == "free" else "1 ficha"
		],
		1244.0, 20, Paleta.CREME
	)

## A ficha de um botão mapeado: qual controle, qual índice, e um contador
## que sobe a cada aperto. O contador é o que prova que o mapeamento
## pegou — sem ele, o técnico aperta o botão e não sabe se o problema é a
## placa, o índice ou o jogo.
func _ficha_do_botao(mapa: Dictionary, titulo: String, rect: Rect2, contador: int) -> void:
	_cartao(rect, Color("240810"), Paleta.CARTAO_BORDA, 1.0, 2.0)
	_texto(titulo, rect.position.y + 34.0, 20, Paleta.CREME, HORIZONTAL_ALIGNMENT_CENTER, rect.position.x, rect.size.x)
	var indice := int(mapa.get("index", -1))
	_texto(
		"BOTÃO %d" % indice if indice >= 0 else "NÃO MAPEADO",
		rect.position.y + 68.0, 18,
		Paleta.AMBAR if indice >= 0 else Paleta.VERMELHO,
		HORIZONTAL_ALIGNMENT_CENTER, rect.position.x, rect.size.x
	)
	var nome := str(mapa.get("nome", ""))
	_texto(
		nome if not nome.is_empty() else "controle não identificado",
		rect.position.y + 98.0, 14, Paleta.TINTA_LEVE,
		HORIZONTAL_ALIGNMENT_CENTER, rect.position.x + 8.0, rect.size.x - 16.0
	)
	_texto(
		"apertado %d ×" % contador, rect.position.y + 128.0, 16, Paleta.VERDE,
		HORIZONTAL_ALIGNMENT_CENTER, rect.position.x, rect.size.x
	)

# ------------------------------------------------------------- GOLPE
func _central_golpe() -> void:
	_secao(Rect2(80, 350, 920, 284), "VELOCIDADE E DIFICULDADE", Paleta.CIANO)
	_stepper("vmin", "%.1f m/s" % hit_min_speed, "MÍNIMA  =  0000 PONTOS", Paleta.CIANO)
	_stepper("vmax", "%.1f m/s" % hit_max_speed, "MÁXIMA  =  9999 PONTOS", Paleta.CIANO)
	_stepper(
		"curva", "γ %.2f" % score_exponent,
		"CURVA  %s" % ScoreCurve.difficulty_name(score_exponent), Paleta.ROXO
	)
	_stepper("zona", "%.0f%%" % (score_dead_zone * 100.0), "ZONA MORTA", Paleta.ROXO)

	_secao(Rect2(80, 650, 920, 260), "OS OITO NÍVEIS (0000 – 9999)", Paleta.AMBAR)
	# A régua engordou e a legenda desceu: com a letra no corpo novo, o
	# nome do nível dentro da faixa e a legenda logo abaixo escreviam um
	# por cima do outro.
	_regua_dos_niveis(Rect2(110, 700, 860, 46))
	_texto(
		"As faixas são fixas. Quem decide quanta gente chega a cada uma é a curva.",
		772.0, 15, Paleta.TINTA_FRACA
	)
	_curva_desenhada(Rect2(110, 782, 860, 56))
	_botao(BOTOES_SIMPLES["calibrar"], "ASSISTENTE DE CALIBRAÇÃO", false, Paleta.VERDE, 20)

	_secao(Rect2(80, 926, 920, 300), "SENSOR DE SOCO (MPU-6050)", Paleta.ROXO)
	var dot := Paleta.VERDE if _sensor_ligado() else Paleta.AMBAR
	draw_circle(Vector2(560, 972.0), 7.0, dot, true, -1.0, true)
	_texto(serial_status, 978.0, 15, Paleta.para_texto(dot), HORIZONTAL_ALIGNMENT_LEFT, 578.0, 400.0)
	_stepper(
		"porta",
		porta_configurada if not porta_configurada.is_empty() else "AUTO",
		"PORTA SERIAL — FIXA" if not porta_configurada.is_empty() else "PORTA SERIAL — AUTOMÁTICA",
		Paleta.CIANO
	)
	_botao(BOTOES_SIMPLES["eixo"], "EIXO  %s" % sensor_eixo, false, Paleta.ROXO, 20)
	_texto("EIXO DO GOLPE", 1102.0, 15, Paleta.TINTA_FRACA, HORIZONTAL_ALIGNMENT_CENTER, BOTOES_SIMPLES["eixo"].position.x, BOTOES_SIMPLES["eixo"].size.x)
	_stepper("raio", "%.2f m" % sensor_raio, "RAIO DO BRAÇO", Paleta.CIANO)
	_stepper("amin", "%.1f g" % sensor_amin, "SENSIBILIDADE", Paleta.CIANO)

	_secao(Rect2(80, 1252, 920, 120), "AÇÕES NO FIRMWARE", Paleta.VERDE)
	_botao(BOTOES_SIMPLES["enviar_config"], "ENVIAR CONFIG", false, Paleta.VERDE, 19)
	_botao(BOTOES_SIMPLES["testar"], "TESTAR SENSOR", false, Paleta.AMBAR, 19)

	_texto(
		telemetria if telemetria != "" else "sem telemetria ainda",
		1420.0, 15, Paleta.TINTA_FRACA, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)
	if not saturacao_recente.is_empty():
		_texto(
			"SATURAÇÃO DO SENSOR: %s — aumente a faixa do MPU-6050" % saturacao_recente,
			1452.0, 15, Paleta.VERMELHO, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
		)

## A CURVA DESENHADA, do jeito que ela vai pagar.
##
## Um expoente é um número abstrato: a diferença entre 2,80 e 3,20 só
## existe no traço. Quem regula precisa VER o que a mudança faz antes de
## salvar, senão regula por tentativa e erro em cima da fila do salão.
func _curva_desenhada(rect: Rect2) -> void:
	_cartao(rect, Color("1c060c"), Paleta.CARTAO_BORDA, 1.0, 1.5)
	var amostras := ScoreCurve.amostrar(hit_min_speed, hit_max_speed, score_exponent, score_dead_zone, 64)
	if amostras.is_empty():
		return
	var v_max: float = (amostras[amostras.size() - 1] as Vector2).x
	var pontos := PackedVector2Array()
	for a in amostras:
		var p: Vector2 = a
		pontos.append(Vector2(
			rect.position.x + rect.size.x * clampf(p.x / maxf(v_max, 0.01), 0.0, 1.0),
			rect.end.y - rect.size.y * clampf(p.y / float(GameDef.SCORE_MAX), 0.0, 1.0)
		))
	draw_polyline(pontos, Paleta.AMBAR, 3.0, true)
	_texto("0 m/s", rect.end.y + 20.0, 13, Paleta.TINTA_LEVE, HORIZONTAL_ALIGNMENT_LEFT, rect.position.x, rect.size.x)
	_texto("%.0f m/s" % v_max, rect.end.y + 20.0, 13, Paleta.TINTA_LEVE, HORIZONTAL_ALIGNMENT_RIGHT, rect.position.x, rect.size.x)

# ------------------------------------------------------------ CÂMERA
func _central_camera() -> void:
	_secao(Rect2(80, 350, 920, 500), "CÂMERA DAS FOTOS DO RANKING", Paleta.ROSA)
	_botao(BOTOES_SIMPLES["camera"], "CÂMERA ON" if camera_enabled else "CÂMERA OFF", camera_enabled, Paleta.ROXO, 16)
	_botao(BOTOES_SIMPLES["trocar_camera"], "TROCAR CÂMERA", false, Paleta.CIANO, 16)
	_botao(BOTOES_SIMPLES["foto_teste"], "TESTAR FOTO", false, Paleta.ROSA, 16)
	_botao(
		BOTOES_SIMPLES["forcar_ponte"],
		"PONTE FORÇADA" if camera_forcar_ponte else "USAR PONTE PYTHON",
		camera_forcar_ponte, Paleta.VERDE, 16
	)
	_botao(BOTOES_SIMPLES["sondar_camera"], "PROCURAR CÂMERA DE NOVO", false, Paleta.CIANO, 16)
	var previa := Rect2(340, 556, 400, 220)
	_cartao(previa, Color("1c060c"), Paleta.CARTAO_BORDA, 1.0, 2.0)
	if camera_service != null and camera_service.estado == CameraService.Estado.EXAME:
		# DURANTE O EXAME A PRÉVIA FICA VAZIA DE PROPÓSITO — a webcam é do
		# diagnóstico, e só um programa por vez a abre. Sem dizer isso na
		# tela, o vazio lê como a câmera tendo caído de novo.
		_draw_avatar(previa, 1.0)
		_carregando(previa.get_center(), 34.0, Paleta.CIANO)
		_texto(
			"EXAMINANDO — A CÂMERA VOLTA NO FIM", previa.end.y + 34.0, 17,
			Paleta.CIANO, HORIZONTAL_ALIGNMENT_CENTER, previa.position.x - 100.0, previa.size.x + 200.0
		)
	elif camera_service != null and camera_service.tem_imagem():
		_draw_texture_cover(camera_service.preview_texture(), previa, 1.0, camera_mirrored)
	else:
		_texto("SEM IMAGEM", previa.position.y + previa.size.y * 0.5, 22, Paleta.TINTA_LEVE)
	var cam_status := camera_service.status if camera_service != null else "SEM SERVIÇO"
	_texto(cam_status, 806.0, 16, Paleta.TINTA_FRACA)
	if camera_service != null:
		_texto(
			camera_service.ficha_da_ponte(), 806.0, 16, Paleta.CIANO,
			HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
		)
	var religadas := camera_service.reinicios_da_ponte() if camera_service != null else 0
	if religadas > 0:
		_texto(
			"ponte religada %d × nesta sessão — se for muito, troque o cabo ou a porta USB" % religadas,
			830.0, 14, Paleta.AMBAR
		)

	# ---- o relatório, na tela, e não numa janela que abre atrás do jogo
	_secao(Rect2(80, 866, 920, 420), "DIAGNÓSTICO DA CÂMERA", Paleta.AMBAR)
	var ocupado := medico != null and medico.rodando
	_botao(BOTOES_SIMPLES["diagnosticar"], "AGUARDE…" if ocupado else "DIAGNOSTICAR", ocupado, Paleta.CIANO, 18)
	_botao(BOTOES_SIMPLES["instalar_camera"], "RESOLVER TUDO", false, Paleta.VERDE, 18)
	if ocupado:
		# O exame roda numa linha à parte e pode levar dois minutos. Sem
		# este anel, os dois minutos são indistinguíveis de um botão que
		# não fez nada — que foi exatamente a queixa que trouxe até aqui.
		_carregando(Vector2(540.0, 1010.0), 26.0, Paleta.CIANO)
	if medico == null or medico.linhas.is_empty():
		_texto(
			"O jogo NÃO precisa de Python: ele tenta a câmera pelo caminho nativo primeiro.",
			1006.0, 15, Paleta.CIANO
		)
		_texto(
			"Só se esse caminho falhar é que a ponte entra — e é ela que pede Python e OpenCV.",
			1030.0, 15, Paleta.TINTA_FRACA
		)
		_texto(
			"DIAGNOSTICAR só olha. RESOLVER TUDO instala o que faltar e libera a privacidade.",
			1054.0, 15, Paleta.TINTA_FRACA
		)
	else:
		for i in range(medico.linhas.size()):
			var linha := str(medico.linhas[i])
			# Aviso em vermelho, resposta comum em creme: quem olha de
			# relance precisa achar o problema sem ler tudo.
			var grave := linha == linha.to_upper() and linha.length() > 12
			_texto(
				linha, 1000.0 + float(i) * 22.0, 15,
				Paleta.VERMELHO if grave else Paleta.CREME,
				HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
			)
	if medico != null and not medico.indices.is_empty():
		_texto(
			"CÂMERAS ENCONTRADAS NOS ÍNDICES: %s" % _lista_de_indices(medico.indices),
			1256.0, 17, Paleta.VERDE
		)

	_secao(Rect2(80, 1302, 920, 290), "MESA DE SOM", Paleta.VERDE)
	_stepper("vol_musica", "%+.0f dB" % volume_musica, "TRILHA", Paleta.CIANO)
	_stepper("vol_efeitos", "%+.0f dB" % volume_efeitos, "EFEITOS E VOZ", Paleta.AMBAR)
	_botao(BOTOES_SIMPLES["testar_som"], "TOCAR SOCO DE TESTE", false, Paleta.VERDE, 19)

# ------------------------------------------------------------- DADOS
func _central_dados() -> void:
	_secao(Rect2(80, 350, 920, 220), "MELHORES DA CASA", Paleta.VERMELHO)
	_lista_do_ranking(Rect2(110, 410, 860, 42))
	var resumo := StatisticsStore.summary(statistics)
	_texto(
		"Hoje %d  •  7 dias %d  •  média %04d  •  Top 5: %d" % [resumo["today"], resumo["last7"], resumo["average"], resumo["top5_entries"]],
		502.0, 16, Paleta.TINTA_LEVE, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)
	_texto("Recorde da casa: %04d" % _melhor(), 532.0, 18, Paleta.AMBAR, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0)

	# A SEÇÃO CRESCEU PORQUE AS LINHAS NÃO CABIAM — e não caber não era
	# um detalhe de estética: as três últimas linhas do diagnóstico
	# ("portas vistas", "sensor" e "caminho até a placa") eram desenhadas
	# em 832, 860 e 888, dentro de uma caixa que terminava em 780. Elas
	# caíam POR CIMA das linhas da seção seguinte, que começa em 796 e
	# escreve em 858 e 888. Duas frases no mesmo pixel, e qual das duas
	# fica por cima depende da fonte e da escala da tela — que é
	# exatamente por que o diagnóstico saía DIFERENTE em cada PC, com a
	# mesma placa e o mesmo jogo. Quem lê a tela para contar ao telefone
	# o que está escrito estava lendo duas frases embaralhadas.
	_secao(Rect2(80, 600, 920, 470), "DIAGNÓSTICO DA PLACA", Paleta.CIANO)
	_texto(serial_status, 664.0, 16, Paleta.TINTA_FRACA, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0)
	_texto(
		telemetria if telemetria != "" else "sem telemetria ainda",
		692.0, 15, Paleta.TINTA_LEVE, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)
	_texto(
		"Zero Delay:  START %d apertos  •  CRÉDITO %d apertos" % [contador_start, contador_credito],
		720.0, 15, Paleta.TINTA_LEVE, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)
	# APERTE O BOTÃO E OLHE ESTES DOIS NÚMEROS.
	#
	# O primeiro é o pino CRU, como a placa o lê agora — o fio. O segundo
	# é quantos apertos o jogo aceitou. "O botão não funciona" tem quatro
	# causas com o mesmo sintoma: fio solto, pino errado, placa muda, ou o
	# jogo ignorando. Estas duas linhas separam as quatro em dez segundos:
	# pino que não muda é problema ANTES do firmware, e aí não adianta
	# mexer em código.
	_texto(
		"pinos agora:  D2 START %s  •  D3 CRÉDITO %s" % [
			"APERTADO" if pino_start else "solto",
			"APERTADO" if pino_credito else "solto",
		],
		748.0, 17,
		Paleta.VERDE if (pino_start or pino_credito) else Paleta.TINTA_LEVE,
		HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)
	_texto(
		"Arduino (D2/D3):  START %d apertos  •  CRÉDITO %d apertos" % [serial_start, serial_credito],
		776.0, 17,
		Paleta.VERDE if (serial_start + serial_credito) > 0 else Paleta.TINTA_LEVE,
		HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)
	_texto(
		"portas vistas: %s" % (", ".join(portas_visiveis) if not portas_visiveis.is_empty() else "nenhuma"),
		832.0, 15, Paleta.TINTA_LEVE, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)
	# POR ONDE O JOGO ESTÁ FALANDO COM A PLACA.
	#
	# Deixou de ser uma pergunta de sim ou não quando a ponte por processo
	# entrou: hoje há dois caminhos, e saber QUAL está em uso é o que
	# separa "o .dll não veio" de "o PowerShell recusou".
	var tem_serial := link != null and link.available()
	var recado_serial := link.descricao() if tem_serial else "NENHUM"
	if link != null and not link.motivo_da_falta().is_empty():
		recado_serial += " — %s" % link.motivo_da_falta()
	_texto(
		"caminho até a placa: %s" % recado_serial,
		860.0, 17, Paleta.VERDE if tem_serial else Paleta.VERMELHO,
		HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)
	# AS DUAS PERGUNTAS, SEPARADAS. "A placa respondeu" e "o sensor
	# respondeu" deixaram de ser a mesma coisa quando o firmware parou de
	# travar sem sensor — e é justamente essa separação que diz ao técnico
	# se ele deve olhar o cabo USB ou os fios do I2C.
	_texto(
		"sensor MPU-6050: %s" % ("presente" if sensor_presente else "NÃO ENCONTRADO — confira SDA=A4, SCL=A5, VCC e GND"),
		888.0, 17, Paleta.VERDE if sensor_presente else Paleta.AMBAR,
		HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)
	# A EXTENSÃO NATIVA CARREGOU? A PERGUNTA QUE FALTAVA, e a que explica
	# o "funciona no meu PC" inteiro.
	#
	# A `gdserial` é um .dll que viaja AO LADO do executável, não dentro
	# dele — copiar só o .exe para outra máquina deixa a extensão para
	# trás. E, mesmo indo junto, ela precisa do runtime do Visual C++
	# 2015-2022 (o VCRUNTIME140.dll), que NÃO vem numa instalação limpa do
	# Windows: no PC de quem desenvolve ele está sempre lá, no PC do
	# cliente quase nunca. Nos dois casos o Windows recusa o .dll em
	# silêncio, sem erro nenhum na tela.
	#
	# Isso não derruba mais a máquina — a ponte assume e o jogo trabalha
	# igual. Mas o técnico precisa poder LER isso, porque é a diferença
	# entre "esta máquina está usando o plano B" e "esta máquina está
	# quebrada".
	var nativa_ok := ClassDB.class_exists(&"GdSerialManager")
	_texto(
		"extensão nativa: %s" % (
			"carregada" if nativa_ok
			else "não carregou — leve gdserial.dll junto do .exe e instale o runtime do Visual C++ 2015-2022"
		),
		916.0, 15, Paleta.VERDE if nativa_ok else Paleta.AMBAR,
		HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)
	# O ANDAMENTO DA BUSCA, EM NÚMEROS.
	#
	# "PROCURANDO ARDUINO…" parado na tela não diz se a máquina está
	# procurando ou travada — e essa dúvida sozinha já custou noites de
	# gabinete. O número da volta subindo é a prova de que a busca está
	# viva, e é o que se lê ao telefone.
	_texto(
		"busca: volta %d  •  porta %d de %d  •  varredura cega %s" % [
			_varreduras + 1, _porta_da_vez, _fila_de_portas.size(),
			"LIGADA" if _cega_liberada else "desligada",
		],
		944.0, 15, Paleta.TINTA_LEVE, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)
	# O QUE JÁ DEU ERRADO NESTA SESSÃO. Ponte religando sem parar é cabo
	# ruim, antivírus ou PowerShell bloqueado; caminho trocando sem parar
	# é uma máquina em que nenhum dos dois presta.
	var religadas_da_ponte := 0
	if link is PonteProcessoLink:
		religadas_da_ponte = (link as PonteProcessoLink).religadas()
	_texto(
		"ponte religada %d ×  •  caminho trocado %d ×" % [
			religadas_da_ponte, _trocas_de_caminho
		],
		972.0, 15,
		Paleta.TINTA_LEVE if (religadas_da_ponte + _trocas_de_caminho) < 4 else Paleta.AMBAR,
		HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)
	# A PORTA FIXADA, E QUANTO CRÉDITO AINDA RESTA A ELA. Fixar uma porta
	# errada era o jeito mais fácil de matar a máquina, e não havia como
	# ver isso em lugar nenhum.
	_texto(
		"porta escolhida: %s" % (
			"automática (varre todas)" if porta_configurada.is_empty()
			else "%s — %d falha(s); %s" % [
				porta_configurada, _falhas_da_porta_fixa,
				"ainda exclusiva" if _falhas_da_porta_fixa < FALHAS_ATE_SOLTAR_A_PORTA_FIXA
				else "liberada, varrendo todas"
			]
		),
		1000.0, 15,
		Paleta.TINTA_LEVE if porta_configurada.is_empty() else Paleta.CIANO,
		HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)
	_texto(
		"sistema: %s  •  velocidade %d bauds" % [OS.get_name(), GameDef.SERIAL_BAUD],
		1028.0, 15, Paleta.TINTA_LEVE, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)

	# ---- O QUE A MÁQUINA ESTÁ ENTREGANDO DE VERDADE
	#
	# "A animação está travada" é a queixa mais difícil de consertar,
	# porque quem programa nunca vê: aqui roda liso, e o gabinete tem
	# outro vídeo, outra TV, outra resolução. Sem número, o conserto vira
	# palpite. Estas quatro linhas são o número — e é o que se manda para
	# quem for consertar, em vez de "está travado".
	_secao(Rect2(80, 1090, 920, 190), "RITMO DA MÁQUINA", Paleta.VERDE)
	var fps := desempenho.fps()
	var cor_fps := Paleta.VERDE if fps >= 55.0 else (Paleta.AMBAR if fps >= 40.0 else Paleta.VERMELHO)
	_texto(
		"%.0f quadros por segundo  •  pior quadro %.1f ms  •  efeitos em %d%%" % [
			fps, desempenho.pior_ms(), int(round(desempenho.qualidade * 100.0))
		],
		1152.0, 20, cor_fps, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)
	_texto(
		"%d chamadas de desenho  •  %d primitivas por quadro" % [
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		],
		1182.0, 17, Paleta.TINTA_LEVE, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)
	# A ESCALA DENUNCIA A TELA DEITADA.
	#
	# O jogo é 1080x1920 em pé. Numa TV deitada, o Godot encolhe tudo
	# para caber na altura e sobra tarja preta dos dois lados: a letra
	# fica com metade dos pixels e a máquina parece de baixa qualidade
	# sem nada estar errado no jogo. Escala 1,00 é a TV girada certo.
	var escala := get_window().get_final_transform().get_scale()
	var aviso := "" if absf(escala.y - 1.0) < 0.02 else "  ← GIRE A TELA NO WINDOWS PARA 1080x1920"
	_texto(
		"janela %dx%d  •  escala %.2f%s" % [
			DisplayServer.window_get_size().x, DisplayServer.window_get_size().y, escala.y, aviso
		],
		1212.0, 17, Paleta.TINTA_LEVE if aviso.is_empty() else Paleta.AMBAR,
		HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)
	_texto(
		"câmera: %s" % (camera_service.status if camera_service != null else "—"),
		1242.0, 17, Paleta.CIANO, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)
	# O TETO À MÃO, para quando o automático errar. Ele acerta na maioria
	# das máquinas e erra em duas: num PC que oscila, ficando subindo e
	# descendo a qualidade o tempo todo, e num PC bom em que o operador
	# prefere menos efeito por gosto.
	_botao(
		BOTOES_SIMPLES["teto_efeitos"], "EFEITOS: %s" % desempenho.teto,
		desempenho.teto != "AUTO", Paleta.ROXO, 17
	)

	_secao(Rect2(80, 1304, 920, 160), "APAGAR (PEDE CONFIRMAÇÃO)", Paleta.VERMELHO)
	_botao(BOTOES_SIMPLES["zerar"], "CONTADORES", false, Paleta.VERMELHO, 14)
	_botao(BOTOES_SIMPLES["zerar_stats"], "ESTATÍSTICAS", false, Paleta.ROXO, 14)
	_botao(BOTOES_SIMPLES["zerar_ranking"], "RANKING + FOTOS", false, Paleta.VERMELHO, 13)
	_botao(BOTOES_SIMPLES["reconectar"], "RECONECTAR", false, Paleta.CIANO, 14)

## Os índices achados, em uma linha. Escrito à mão porque um `map` com
## lambda aqui não deixa o GDScript inferir o tipo, e tipo inferido é o
## que faz este arquivo compilar rápido.
func _lista_de_indices(valores: Array) -> String:
	var partes := PackedStringArray()
	for v in valores:
		partes.append(str(v))
	return ", ".join(partes)

## Manda examinar a instalação da câmera. `instalar` autoriza mexer no
## sistema; sem ele o exame só olha e conta.
## O SOCORRO: A MÁQUINA SE EXAMINA SOZINHA.
##
## Até aqui o diagnóstico era um botão, e um botão só serve para quem
## sabe que ele existe, sabe abrir a Central e está na frente do
## gabinete. Quem liga a máquina no salão às oito da noite não é essa
## pessoa — e uma câmera que não sobe ficava sem imagem a noite inteira
## sem ninguém saber por quê.
##
## Doze segundos depois de ligar, se ainda não veio quadro nenhum, a
## máquina roda o exame por conta própria e ADOTA o que descobrir: o
## índice, o back-end e o interpretador. Uma vez por sessão — se o exame
## não resolveu, repeti-lo de minuto em minuto não resolve também, e
## ainda ocupa a linha de execução no meio das partidas.
const SOCORRO_ESPERA := 12.0
var _socorro_relogio := 0.0
var _socorro_feito := false

func _socorro_da_camera(delta: float) -> void:
	if _socorro_feito or camera_service == null or medico == null:
		return
	if not camera_enabled or camera_service.available():
		# Já veio imagem: não há o que socorrer, e a contagem não recomeça
		# — uma câmera que caiu depois de funcionar é caso da religação
		# automática da ponte, não do exame.
		_socorro_feito = camera_service.available()
		return
	_socorro_relogio += delta
	if _socorro_relogio < SOCORRO_ESPERA or medico.rodando:
		return
	_socorro_feito = true
	_examinar_camera(false)

func _examinar_camera(resolver: bool) -> void:
	if medico == null or medico.rodando:
		return
	# A PONTE SAI DO AR ANTES DA SONDAGEM. Os dois disputando a webcam é
	# o que fazia a imagem piscar na Central: um abre, o outro perde, o
	# vigia religa, e assim sem parar.
	camera_service.pedir_exame()
	medico.diagnosticar(
		resolver, camera_service.caminho_da_ponte(), camera_service.caminho_do_inspetor()
	)
	_show_notice("EXAMINANDO — A RESPOSTA APARECE NA TELA")

## Terminado o exame, a máquina AGE com o que descobriu: se achou câmera
## num índice, passa a usar aquele índice e reabre. Um relatório que
## exige o técnico repetir à mão o que a máquina acabou de descobrir é
## meio relatório.
func _fim_do_exame() -> void:
	# O INTERPRETADOR VALE MESMO SEM ÍNDICE. Se o exame confirmou um
	# Python com OpenCV, guardá-lo já conserta a próxima tentativa da
	# ponte — mesmo que a câmera estivesse ocupada no instante da sonda.
	if not medico.python.is_empty() and medico.tem_opencv:
		camera_python = medico.python
		camera_python_args = ",".join(medico.python_args)
		camera_service.adotar_python(medico.python, medico.python_args)
		_salvar()
	if medico.indices.is_empty():
		# Sem índice, a ponte volta ao ar mesmo assim: ela varre os
		# índices sozinha, e a webcam pode ter estado ocupada só no
		# instante da sondagem.
		camera_service.terminar_exame()
		if camera_enabled and not medico.linhas.is_empty():
			_show_notice(str(medico.linhas[medico.linhas.size() - 1]))
		return
	camera_index = int(medico.indices[0])
	camera_service.selected_index = camera_index
	# O BACK-END TAMBÉM É DESCOBERTA, e também vale guardar. Sem ele a
	# ponte refaz a fila DirectShow → Media Foundation → qualquer um a
	# cada religada, e cada tentativa frustrada custa segundos no Windows
	# — segundos que caem justamente na hora de tirar a foto.
	camera_backend = medico.backend
	camera_service.backend_preferido = camera_backend
	# O INTERPRETADOR PROVADO. É a peça que faltava: o exame achava tudo
	# certo e o jogo continuava subindo a ponte com outro Python.
	camera_python = medico.python
	camera_python_args = ",".join(medico.python_args)
	camera_service.adotar_python(medico.python, medico.python_args)
	camera_enabled = true
	camera_service.enabled = true
	camera_service.terminar_exame()
	_salvar()
	_show_notice("CÂMERA NO ÍNDICE %d%s — RELIGANDO" % [
		camera_service.selected_index,
		"" if medico.backend.is_empty() else " VIA " + medico.backend,
	])

## As cinco marcas em uma linha só: o técnico precisa VER o que vai
## apagar antes de apertar ZERAR RANKING.
func _lista_do_ranking(rect: Rect2) -> void:
	var largura := (rect.size.x - 4.0 * 10.0) / 5.0
	for i in range(5):
		var celula := Rect2(rect.position + Vector2(i * (largura + 10.0), 0.0), Vector2(largura, rect.size.y))
		var cor := _cor_da_posicao(i + 1)
		var tem := i < ranking.size()
		_cartao(celula, Paleta.tinta_clara(cor, 0.14) if tem else Paleta.VAZIO, Paleta.CARTAO_BORDA, 1.0, 0.0)
		_texto("%dº" % (i + 1), celula.position.y + 20.0, 13, Color(Paleta.para_texto(cor)), HORIZONTAL_ALIGNMENT_CENTER, celula.position.x, celula.size.x)
		_texto(
			"%04d" % RankingStore.score_at(ranking, i) if tem else "—", celula.position.y + 44.0, 22,
			Paleta.TINTA if tem else Paleta.TINTA_LEVE,
			HORIZONTAL_ALIGNMENT_CENTER, celula.position.x, celula.size.x
		)

## Uma seção da Central: moldura e título, sempre no mesmo lugar em
## relação à caixa. Nenhuma seção precisa saber onde fica o seu rótulo.
func _secao(rect: Rect2, titulo: String, cor := Paleta.MARINHO) -> void:
	# A seção mais baixa da página é o que define até onde a rolagem vai.
	# Medir aqui, e não numa tabela de alturas, é o que faz a rolagem
	# continuar certa quando alguém mover uma seção daqui a seis meses.
	central_fundo = maxf(central_fundo, rect.end.y)
	_cartao(rect, Paleta.tinta_clara(Paleta.MARINHO, 0.045), Paleta.CARTAO_BORDA, 1.0, 0.0)
	# Tarja colorida na lateral: com sete seções empilhadas, é o que deixa
	# o técnico achar a que procura sem ler todos os títulos.
	draw_rect(Rect2(rect.position, Vector2(8.0, rect.size.y)), cor)
	_texto(titulo, rect.position.y + 40.0, 16, Paleta.para_texto(cor), HORIZONTAL_ALIGNMENT_LEFT, rect.position.x + 40.0, rect.size.x - 80.0)

## Um par − / + com o valor no meio e a legenda embaixo. Os retângulos
## saem de `PASSOS`, os mesmos que o clique consulta — texto e área de
## toque não têm como divergir.
func _stepper(chave: String, valor: String, legenda: String, accent: Color) -> void:
	var visor := _passo_visor(chave)
	_cartao(visor, Paleta.CARTAO, Paleta.CARTAO_BORDA, 1.0, 0.0)
	_botao(_passo_menos(chave), "−", false, accent, 26)
	_botao(_passo_mais(chave), "+", false, accent, 26)
	_texto_cabendo(valor, visor.position.y + visor.size.y * 0.68, 30, Paleta.TINTA, visor.size.x - 12.0, visor.position.x + 6.0)
	var r: Rect2 = PASSOS[chave]
	_texto(legenda, r.end.y + 28.0, 15, Paleta.TINTA_FRACA, HORIZONTAL_ALIGNMENT_CENTER, r.position.x, r.size.x)

## A RÉGUA DOS OITO NÍVEIS, na largura de cada um.
##
## Ela é de LEITURA: as faixas são fixas e não há o que arrastar aqui. O
## que ela mostra é a desproporção — os quatro níveis de cima ocupam um
## quinto da escala, e é vendo isso que o técnico entende por que quase
## ninguém chega ao topo, em vez de achar que a máquina está quebrada.
func _regua_dos_niveis(rect: Rect2) -> void:
	var teto := float(GameDef.SCORE_MAX + 1)
	for nivel in ScoreTier.NIVEIS:
		var x0 := rect.position.x + rect.size.x * (float(nivel["min"]) / teto)
		var x1 := rect.position.x + rect.size.x * (float(int(nivel["max"]) + 1) / teto)
		draw_rect(Rect2(x0, rect.position.y, x1 - x0, rect.size.y), nivel["cor"] as Color)
		if x1 - x0 > 96.0:
			# Preto sobre cor clara, branco sobre cor escura. A cor do
			# nível é dado de projeto e vai de creme a azul-acinzentado:
			# um contraste fixo apagaria metade dos nomes.
			var cor: Color = nivel["cor"]
			var tinta := Color.BLACK if cor.get_luminance() > 0.55 else Color.WHITE
			_texto(
				str(nivel["nome"]), rect.position.y + rect.size.y * 0.70, 14, tinta,
				HORIZONTAL_ALIGNMENT_CENTER, x0, x1 - x0
			)
	draw_rect(rect, Paleta.CARTAO_BORDA, false, 2.0)
	# O teto da escala fica marcado à direita: é o único ponto da régua
	# que uma pessoa pode alcançar e não é uma faixa, é um alvo.
	_texto("9999", rect.end.y + 22.0, 15, Paleta.CREME, HORIZONTAL_ALIGNMENT_RIGHT, rect.position.x, rect.size.x)
	_texto("0000", rect.end.y + 22.0, 15, Paleta.TINTA_FRACA, HORIZONTAL_ALIGNMENT_LEFT, rect.position.x, rect.size.x)

## Retângulo de cantos redondos. O Godot só desenha retângulo de canto
## vivo, e canto vivo em peça grande destoa do resto da tela — a placa,
## os cartões e os botões todos precisam da mesma família de formas.
func _placa(rect: Rect2, raio: float, cor: Color) -> void:
	Traco.poligono(self, _contorno_arredondado(rect, raio), cor)

func _contorno_arredondado(rect: Rect2, raio: float) -> PackedVector2Array:
	var r := minf(raio, minf(rect.size.x, rect.size.y) * 0.5)
	var pontos := PackedVector2Array()
	var cantos := [
		[Vector2(rect.end.x - r, rect.position.y + r), -PI * 0.5],
		[Vector2(rect.end.x - r, rect.end.y - r), 0.0],
		[Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5],
		[Vector2(rect.position.x + r, rect.position.y + r), PI],
	]
	for c in cantos:
		var meio: Vector2 = c[0]
		var a0: float = c[1]
		for i in range(9):
			var a := a0 + float(i) / 8.0 * PI * 0.5
			pontos.append(meio + Vector2(cos(a), sin(a)) * r)
	return pontos

func _photo_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _photo_cache.has(path):
		return _photo_cache[path] as Texture2D
	if not FileAccess.file_exists(path):
		return null
	# NÃO DECODIFICADA AINDA: melhor um quadro sem foto (o contorno de
	# `_draw_avatar`) do que travar o quadro atual para decodificar na
	# hora. `_agendar_decodificacao` já deve ter posto isto a caminho;
	# se ainda não pôs (foto criada agora mesmo, fora do prewarm), põe.
	_agendar_decodificacao(path)
	return null

## Roda FORA da linha do jogo -- ver o comentário de `_fotos_decodificadas`.
##
## PODE CHEGAR CEDO DEMAIS: a foto do ranking agora é gravada em segundo
## plano por `camera_service.gd` (ver o comentário lá), e o prewarm daqui
## pode rodar antes de o arquivo existir. Por isso o "não encontrei"
## também é reportado -- com `false` em vez de uma imagem -- para
## `_colher_fotos_decodificadas` liberar uma NOVA tentativa, em vez de
## marcar este caminho como "em andamento" para sempre e nunca mais
## tentar de novo.
func _decodificar_foto(path: String) -> void:
	var imagem: Variant = false
	if FileAccess.file_exists(path):
		var candidata := Image.new()
		if candidata.load(ProjectSettings.globalize_path(path)) == OK and not candidata.is_empty():
			imagem = candidata
	_mutex_fotos.lock()
	_fotos_decodificadas[path] = imagem
	_mutex_fotos.unlock()

## Põe uma foto na fila de decodificação, uma vez só por caminho.
var _fotos_em_andamento: Dictionary = {}
func _agendar_decodificacao(path: String) -> void:
	if path.is_empty() or _photo_cache.has(path) or _fotos_em_andamento.has(path):
		return
	_fotos_em_andamento[path] = true
	WorkerThreadPool.add_task(_decodificar_foto.bind(path))

## Chamada assim que uma pontuação entra no ranking: põe as fotos que
## ainda faltam no cache a caminho, com vários segundos de folga antes
## de a tabela do Top 20 precisar mostrá-las de verdade.
func _prewarm_fotos_do_ranking() -> void:
	for entry in ranking:
		_agendar_decodificacao(str(entry.get("photo_path", "")))

## Chamada todo quadro (barata: só olha se algo terminou). Cria a
## textura -- isso sim precisa ser na linha do jogo -- a partir da
## imagem que o pool de linhas já deixou pronta. Um `false` (arquivo
## ainda não gravado, ou corrompido) só libera o caminho para uma nova
## tentativa depois -- `_photo_texture` reagenda sozinho quando alguém
## pedir essa foto de novo.
func _colher_fotos_decodificadas() -> void:
	if _fotos_decodificadas.is_empty():
		return
	_mutex_fotos.lock()
	var prontas := _fotos_decodificadas.duplicate()
	_fotos_decodificadas.clear()
	_mutex_fotos.unlock()
	for path in prontas:
		_fotos_em_andamento.erase(path)
		var imagem = prontas[path]
		if imagem is Image:
			_photo_cache[path] = ImageTexture.create_from_image(imagem)

func _draw_texture_cover(texture: Texture2D, rect: Rect2, alpha: float, mirror := false) -> void:
	if texture == null:
		return
	var source_size := texture.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return
	var source := Rect2(Vector2.ZERO, source_size)
	var source_aspect := source_size.x / source_size.y
	var target_aspect := rect.size.x / rect.size.y
	if source_aspect > target_aspect:
		var wanted_width := source_size.y * target_aspect
		source.position.x = (source_size.x - wanted_width) * 0.5
		source.size.x = wanted_width
	else:
		var wanted_height := source_size.x / target_aspect
		source.position.y = (source_size.y - wanted_height) * 0.5
		source.size.y = wanted_height
	if mirror:
		draw_set_transform(_deslocamento + Vector2(rect.end.x, rect.position.y), 0.0, Vector2(-1.0, 1.0))
		draw_texture_rect_region(texture, Rect2(Vector2.ZERO, rect.size), source, Color(1, 1, 1, alpha))
		draw_set_transform(_deslocamento, 0.0, Vector2.ONE)
	else:
		draw_texture_rect_region(texture, rect, source, Color(1, 1, 1, alpha))

## O LUGAR DA FOTO QUE AINDA NÃO EXISTE.
##
## Um círculo amarelo sobre um trapézio roxo não lê como pessoa: lê como
## erro de desenho, e ainda por cima em duas cores que não são do tema.
## Aqui é uma silhueta de ombros e cabeça, na cor da moldura, com a
## mira de enquadramento por cima — a mesma que uma câmera mostra.
## Assim o quadro vazio diz "é aqui que o seu rosto vai aparecer".
## O LUGAR DA FOTO QUE AINDA NÃO EXISTE.
##
## Ele era um boneco de massa cheia num vinho forte, e vinte deles
## empilhados na tabela do Top 20 leem como uma parede marrom na frente
## do ranking — foi essa a queixa. O que a vaga precisa dizer é "aqui vai
## uma foto", e para isso basta um contorno: linha fina, sem miolo, na
## mesma cor do resto da moldura. Presente o bastante para não virar
## buraco, discreto o bastante para não competir com nada.
func _draw_avatar(rect: Rect2, alpha: float) -> void:
	draw_rect(rect, Color("1c060c", 0.70 * alpha))
	var center := rect.get_center()
	var unit := minf(rect.size.x, rect.size.y)
	var tom := Color("6d2835", 0.55 * alpha)

	# Só o traço: cabeça e ombros em linha, sem massa.
	draw_arc(center + Vector2(0.0, -unit * 0.10), unit * 0.13, 0.0, TAU, 28, tom, unit * 0.035, true)
	draw_arc(
		center + Vector2(0.0, unit * 0.30), unit * 0.25,
		PI * 1.08, PI * 1.92, 26, tom, unit * 0.035, true
	)

	# Cantoneiras de enquadramento, como as de um visor de câmera.
	var margem := unit * 0.10
	var braco := unit * 0.14
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var canto := center + Vector2(sx * (rect.size.x * 0.5 - margem), sy * (rect.size.y * 0.5 - margem))
			draw_line(canto, canto - Vector2(sx * braco, 0.0), Color(Paleta.AMBAR, 0.55 * alpha), 4.0, true)
			draw_line(canto, canto - Vector2(0.0, sy * braco), Color(Paleta.AMBAR, 0.55 * alpha), 4.0, true)

func _draw_player_photo(rect: Rect2, path: String, alpha: float) -> void:
	var texture := _photo_texture(path)
	if texture == null:
		_draw_avatar(rect, alpha)
	else:
		_draw_texture_cover(texture, rect, alpha)
	draw_rect(rect, Color(Paleta.CIANO, alpha), false, 3.0)

## O aviso de operação ocupa o rodapé, e não o topo: no topo ele cairia
## em cima do cabeçalho, e no meio disputaria com o número.
## OS DOIS AVISOS QUE PRECISAM APARECER NA TELA DO JOGO, e não só na
## Central: sem eles a máquina não faz o que foi comprada para fazer, e
## quem está na frente dela não tem como saber por quê.
##
##   * a extensão da serial não carregou — sem ela NÃO HÁ Arduino: nem
##     botão, nem crédito, nem sensor. É o defeito que aparece só no
##     computador novo, porque no PC de quem desenvolve o .dll está
##     sempre lá;
##   * os acentos vieram duplicados — o arquivo foi corrompido na cópia,
##     e quem vê a tela procura o defeito na fonte durante horas.
##
## No rodapé, discretos, e só quando há o que dizer. Uma máquina em
## operação normal nunca os vê.
func _draw_alertas_graves() -> void:
	var recados: Array[String] = []
	if not Versao.acentos_inteiros():
		recados.append(Versao.recado_do_estrago())
	if link != null and not link.available():
		recados.append("SEM CAMINHO ATÉ O ARDUINO — START, CRÉDITO E SENSOR MORTOS")
	if recados.is_empty():
		return
	var altura := 34.0 * float(recados.size()) + 16.0
	var caixa := Rect2(40.0, 1920.0 - altura - 8.0, 1000.0, altura)
	draw_rect(caixa, Color(Paleta.VERMELHO, 0.92))
	draw_rect(caixa, Paleta.AMBAR, false, 2.0)
	for i in range(recados.size()):
		_texto(
			recados[i], caixa.position.y + 26.0 + float(i) * 34.0, 17, Color.WHITE,
			HORIZONTAL_ALIGNMENT_CENTER, caixa.position.x, caixa.size.x
		)

## A peça padrão da tela: retângulo branco com sombra e borda. Todo painel
## do jogo passa por aqui, então a "altura" das peças é a mesma em toda
## parte — e mudar a sombra do jogo inteiro é mudar uma função.
func _cartao(rect: Rect2, fundo_c: Color, borda: Color, alpha := 1.0, largura_borda := 2.0) -> void:
	draw_rect(Rect2(rect.position + Vector2(0, 4.0), rect.size), Color(Paleta.SOMBRA, Paleta.SOMBRA.a * alpha))
	draw_rect(rect, Color(fundo_c, fundo_c.a * alpha))
	if largura_borda > 0.0:
		draw_rect(rect, Color(borda, borda.a * alpha), false, largura_borda)

## Botão: colorido e cheio quando ativo, branco com borda colorida quando
## não. Num tema claro é o PREENCHIMENTO que marca o estado ligado —
## borda mais grossa sozinha não se lê de longe.
func _botao(rect: Rect2, texto: String, ativo: bool, accent: Color, tamanho: int) -> void:
	var fundo_c := accent if ativo else Paleta.CARTAO
	var tinta := Paleta.CARTAO if ativo else Paleta.para_texto(accent)
	draw_rect(Rect2(rect.position + Vector2(0, 3.0), rect.size), Paleta.SOMBRA)
	draw_rect(rect, fundo_c)
	draw_rect(rect, Color(accent, 0.9), false, 2.0)
	_texto_cabendo(
		texto, rect.position.y + rect.size.y * 0.68, tamanho, tinta,
		rect.size.x - 20.0, rect.position.x + 10.0
	)

## Despacha o ícone pelo nome. Um `match` num lugar só evita que cada
## chamada precise saber de qual arquivo o desenho vem.
func _icone(nome: String, centro: Vector2, raio: float, cor: Color) -> void:
	match nome:
		"trofeu":
			Icones.trofeu(self, centro, raio, cor)
		"luva":
			Icones.luva(self, centro, raio, cor)
		"ficha":
			Icones.ficha(self, centro, raio, cor)
		"raio":
			Icones.raio_eletrico(self, centro, raio, cor)
		"alvo":
			Icones.alvo(self, centro, raio, cor)
		"botao":
			Icones.botao(self, centro, raio, cor)
		"estrela":
			Icones.estrela(self, centro, raio, cor)

# ---------------------------------------------------------------- texto
## Todo texto da tela passa por aqui. `y` é a LINHA DE BASE, que é como o
## Godot desenha — e é por isso que as bandas do topo do arquivo falam em
## linha de base e não em topo de caixa.
func _texto(
	texto: String, y: float, tamanho: int, cor: Color,
	alinhamento := HORIZONTAL_ALIGNMENT_CENTER, x := MARGEM, largura := LARGURA_UTIL
) -> void:
	draw_string(fonte_texto, Vector2(x, y), texto, alinhamento, largura, _corpo(tamanho), cor)

## COMPENSAÇÃO DE ALTURA ENTRE AS DUAS LETRAS.
##
## "Tamanho 26" no Godot é a altura da CAIXA da fonte, não a altura da
## letra. A maiúscula da Bungee ocupa 0,720 dessa caixa; a da Saira
## Condensed, 0,688 (medido nas próprias tabelas dos arquivos). Pedir 26
## nas duas desenharia letras de alturas diferentes, e todas as posições
## desta tela foram acertadas com a altura da Bungee.
##
## Este fator devolve a altura: 0,720 / 0,688. Ele NÃO é um "deixa maior
## porque ficou pequeno" — é a conta que faz 26 continuar valendo 26.
const CAIXA_LEITURA := 1.047

## O PISO DO CORPO DE LETRA.
##
## Havia texto a 14 e a 15 px numa tela de 1080 de largura, vista de pé,
## a um metro e meio de distância. Isso não é letra miúda: é letra que
## não se lê, e a pessoa desiste antes de tentar. Dezoito é o menor corpo
## em que a Saira Condensed ainda separa o "0" do "O" nessa distância —
## abaixo disso não adianta melhorar o desenho, tem de crescer.
##
## Quem pede menos que o piso recebe o piso. É por isso que existe um
## piso e não uma revisão de cada chamada: com quarenta lugares pedindo
## tamanho, a próxima linha escrita com 14 voltaria a ser ilegível.
const CORPO_MINIMO := 18

func _corpo(tamanho: int) -> int:
	if fonte_texto == fonte:
		return maxi(CORPO_MINIMO, tamanho)
	return maxi(CORPO_MINIMO, int(round(float(tamanho) * CAIXA_LEITURA)))

## O CACHE DE `_tamanho_que_cabe`.
##
## Esta tela inteira é desenhada à mão, num `_draw()` só, chamado TODO
## quadro — e antes disso aqui era recalculado todo quadro também, para
## todo texto que encolhe: até a palavra "CALIBRAÇÃO", que nunca muda de
## letra nem de largura entre um quadro e o outro, media de novo a cada
## quadro. Cada medição é uma busca linear que pode chegar a quarenta e
## poucas chamadas a `get_string_size`, e a primeira vez que a fonte vê um
## tamanho novo ela ainda desenha o glifo (rasteriza), o que custa muito
## mais que uma medição comum. Era exatamente esse custo, repetido sem
## necessidade a cada quadro, que travava a entrada da tabela de
## classificação e a montagem do letreiro na abertura.
##
## A chave inclui o texto, o teto de tamanho, a largura disponível e a
## fonte usada: as quatro coisas de que o resultado da busca depende. Só
## se elas mudarem — outro placar, outra frase — o cálculo roda de novo.
## Um teto de entradas evita que a máquina, ligada o dia inteiro, acumule
## uma entrada por número de placar diferente para sempre: numa arcada o
## conjunto de textos é pequeno e se repete, então limpar de vez em quando
## custa perto de nada.
const CACHE_TAMANHO_TETO := 400
var _cache_tamanho: Dictionary = {}

## O maior corpo, até `tamanho_max`, em que o texto ainda cabe na
## largura. Sem isso, "PESO-PESADO" a 96 px sai pelos dois lados da tela
## e "FRACO!" fica pequeno demais no mesmo lugar.
func _tamanho_que_cabe(texto: String, tamanho_max: int, largura: float, letra: Font = null) -> int:
	var usada: Font = letra if letra != null else fonte
	var chave := [texto, tamanho_max, largura, usada]
	var em_cache = _cache_tamanho.get(chave)
	if em_cache != null:
		return em_cache

	# A MAIORIA DOS TEXTOS JÁ CABE NO TETO PEDIDO — um rótulo curto como
	# "PONTOS" a 30 px nunca precisou encolher, e pedia a mesma busca de
	# quem precisa. Medir uma vez no teto e só então decidir resolve o
	# caso comum com UMA chamada, não quarenta.
	var tamanho := tamanho_max
	var medido := usada.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho).x
	if medido > largura and medido > 0.0:
		# NÃO COUBE: em vez de descer de dois em dois a partir do teto, a
		# largura medida dá uma ESTIMATIVA direta de quanto encolher — a
		# largura do texto cresce quase linearmente com o corpo da letra.
		# Um chute perto do alvo mais um ajuste fino substitui a busca
		# inteira por poucas chamadas, e o efeito é o mesmo de sempre:
		# encolhido só o necessário para caber.
		tamanho = int(floor(float(tamanho_max) * largura / medido))
		tamanho = clampi(tamanho, 10, tamanho_max)
		tamanho -= tamanho % 2
		# O chute pode errar para os dois lados (a fonte não é
		# perfeitamente linear), então o ajuste fino cobre os dois: sobe
		# se o chute encolheu demais, desce se ainda não coube.
		while tamanho < tamanho_max and usada.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho + 2).x <= largura:
			tamanho += 2
		while tamanho > 10 and usada.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho).x > largura:
			tamanho -= 2

	if _cache_tamanho.size() >= CACHE_TAMANHO_TETO:
		_cache_tamanho.clear()
	_cache_tamanho[chave] = tamanho
	return tamanho

## LETRA DE FLIPERAMA. Três passadas sobre a mesma palavra:
##
##   1. um contorno MUITO grosso, quase preto — é ele que segura a letra
##      sobre qualquer fundo, e é o que separa um letreiro de arcade de
##      um texto colorido qualquer;
##   2. a mesma palavra alguns pixels ACIMA, num tom claro: o que sobra
##      aparecendo por cima da borda vira o brilho do topo da letra, o
##      truque que dá volume sem precisar de degradê (o Godot desenha
##      texto de uma cor só);
##   3. o preenchimento, na cor da vez.
##
## Com `halo`, entra antes de tudo um contorno largo e transparente na
## cor de destaque — a luz que a letra joga no que está atrás dela.
func _letreiro(
	texto: String, pos: Vector2, tamanho: int, cor: Color,
	halo := Color(0, 0, 0, 0), letra: Font = null
) -> void:
	var usada: Font = letra if letra != null else fonte
	if halo.a > 0.001:
		draw_string_outline(usada, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, int(tamanho * 0.34), halo)
	# O CONTORNO ACOMPANHA O CORPO DA LETRA, e não o tamanho pedido.
	#
	# Um contorno de 17% do corpo é o que dá presença a PUNCH a 144 px.
	# Nos 22 px de um rótulo esse mesmo 17% engorda quatro pixels em cada
	# lado de um traço que tem três de largura: o contorno come a letra e
	# sobra a mancha. Abaixo de 34 px o contorno passa a ser fino e fixo,
	# apenas o bastante para descolar a letra do fundo.
	var grossura := maxi(6, int(tamanho * 0.17)) if tamanho >= 34 else maxi(3, int(tamanho * 0.11))
	draw_string_outline(
		usada, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho,
		grossura, Color(Paleta.CONTORNO, cor.a)
	)
	# O realce de topo também é coisa de letra grande: a 22 px ele vira
	# uma segunda cópia deslocada meio pixel, que é a definição de borrão.
	if tamanho >= 34:
		var realce := Color(cor.lightened(0.42), cor.a)
		draw_string(usada, pos - Vector2(0.0, tamanho * 0.055), texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, realce)
	draw_string(usada, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, cor)

## OS TRÊS PAPÉIS DE TEXTO DA TELA DE JOGO.
##
## Antes cada linha escolhia o seu corpo na hora — 25, 26, 30, 32, 34, 46
## — e metade delas era `draw_string` cru, sem contorno, sobre um painel
## que muda de cor a cada faixa. O resultado era uma tela com sete
## tamanhos e dois acabamentos diferentes, e é isso que faz uma tela
## parecer amadora, mesmo quando cada peça sozinha está certa.
##
## Agora há três papéis e nada mais:
##
##   TÍTULO  o que a pessoa lê de longe. Letreiro com contorno e halo,
##           igual ao da abertura — é a mesma tipografia do cartaz.
##   RÓTULO  o que nomeia um número: "CALCULANDO", "PONTOS". Sempre 26,
##           sempre com contorno, porque ele cai sobre o painel escuro,
##           sobre a faixa vermelha e sobre o clarão do soco.
##   APOIO   a letra miúda de quem quiser conferir. Sempre 22.
##
## Todos com o mesmo contorno da abertura: é isso que "uniformiza com as
## iniciais" de verdade, e não só igualar o corpo da letra.
## A Saira Condensed é um terço mais estreita que a Bungee (0,474 contra
## 0,712 de largura média na maiúscula). Essa largura devolvida é o que
## permite subir o corpo dos dois papéis sem que nada estoure a linha: a
## tela ganha letra maior E linha mais curta ao mesmo tempo, que é o que
## faltava para ler de longe.
const CORPO_ROTULO := 30
const CORPO_APOIO := 25

func _rotulo(texto: String, y: float, cor: Color) -> void:
	_letreiro_centrado(texto, y, _corpo(CORPO_ROTULO), cor, fonte_texto)

func _apoio(texto: String, y: float, cor: Color) -> void:
	_letreiro_centrado(texto, y, _corpo(CORPO_APOIO), cor, fonte_texto)

## A MARCA DA CASA, DESENHADA E NÃO ESCRITA.
##
## Escrever "LAZER & SPORT GAMES" com a fonte do jogo não é a marca: é
## uma frase com o nome da marca. O alvo com o dardo é o que se reconhece
## a três metros, antes de conseguir ler qualquer coisa — e é ele que
## está no adesivo do gabinete, no cartão e na fachada.
##
## `y` é o TOPO do logotipo, e não a linha de base: aqui não há linha de
## base, há uma imagem com altura própria.
func _marca_da_casa(y: float, altura: float, alpha := 1.0) -> void:
	if logo == null:
		# Sem o arquivo, a frase volta — uma abertura sem marca nenhuma
		# seria pior do que uma abertura com a marca escrita.
		_texto("LAZER & SPORT GAMES", y + altura * 0.72, 28, Color(Paleta.CIANO, alpha))
		return
	var proporcao := logo.get_width() / float(logo.get_height())
	var largura := altura * proporcao
	draw_texture_rect(
		logo, Rect2(Vector2(540.0 - largura * 0.5, y), Vector2(largura, altura)),
		false, Color(1, 1, 1, alpha)
	)

## A MARCA DA CASA À DIREITA, discreta, na linha `y`.
##
## Ela NÃO entra na tela de contagem com o número grande: ali a atenção
## tem de ir para o 3-2-1 e para a câmera, e uma marca ao lado é uma
## segunda coisa pedindo o olho no segundo em que a pessoa está se
## ajeitando para a foto.
func _marca_lateral(y: float, alpha := 0.85, altura := 96.0) -> void:
	if logo == null:
		return
	var largura := altura * logo.get_width() / float(logo.get_height())
	draw_texture_rect(
		logo, Rect2(Vector2(1000.0 - largura, y), Vector2(largura, altura)),
		false, Color(1, 1, 1, alpha)
	)

## Letreiro centrado na largura útil, sem encolher: o corpo dos rótulos é
## fixo de propósito, e um rótulo que não cabe é um rótulo comprido
## demais, não um rótulo que precisa diminuir.
func _letreiro_centrado(texto: String, y: float, tamanho: int, cor: Color, letra: Font = null) -> void:
	var usada: Font = letra if letra != null else fonte
	var medida := usada.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho)
	_letreiro(texto, Vector2(540.0 - medida.x * 0.5, y), tamanho, cor, Color(0, 0, 0, 0), usada)

## Letreiro centrado numa largura, encolhendo até caber.
func _texto_arcade(texto: String, y: float, tamanho_max: int, cor: Color, largura: float, x := MARGEM) -> void:
	var tamanho := _tamanho_que_cabe(texto, tamanho_max, largura * 0.94)
	var medida := fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho)
	_letreiro(texto, Vector2(x + (largura - medida.x) * 0.5, y), tamanho, cor, Color(cor, 0.28))

func _texto_cabendo(texto: String, y: float, tamanho_max: int, cor: Color, largura: float, x := MARGEM) -> void:
	draw_string(
		fonte_texto, Vector2(x, y), texto, HORIZONTAL_ALIGNMENT_CENTER, largura,
		_tamanho_que_cabe(texto, _corpo(tamanho_max), largura, fonte_texto), cor
	)
