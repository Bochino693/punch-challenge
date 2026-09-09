shader_type canvas_item;
render_mode blend_mix, unshaded;

// BRILHO QUE CORRE DENTRO DAS LETRAS.
//
// O efeito antigo era uma faixa de luz DESENHADA POR CIMA do letreiro:
// três quadriláteros atravessando a tela na altura do nome. Como o
// quadrilátero não sabe onde a letra está, a luz aparecia também no
// espaço entre as letras e em volta delas — e o que se via era um
// retângulo luminoso passando, não um reflexo no letreiro.
//
// Aqui quem decide onde há luz é a PRÓPRIA LETRA. O fragmento só existe
// onde o glifo tem tinta; fora dele o shader nem é executado. É a
// diferença entre pintar sobre o nome e o nome refletir.
//
// Custo: nenhum desenho a mais. É o mesmo `draw_string` de sempre, com
// uma conta por pixel de letra — algumas dezenas de milhares de pixels,
// que é ruído perto dos vinte mil triângulos que esta tela já desenha.

// A faixa horizontal onde o nome vive, em coordenadas locais do nó.
// Sem ela a conta teria de sair da UV do glifo, que é a posição dentro
// do ATLAS da fonte — cada letra recomeçaria o brilho do zero e o efeito
// viraria um piscar simultâneo em todas elas.
uniform float inicio_x = 0.0;
uniform float extensao_x = 1080.0;

// Onde a faixa está agora, de -0.2 (antes de entrar) a 1.2 (já saiu).
uniform float posicao = -0.5;

// Largura da faixa em fração da extensão. Estreita: é um reflexo, não
// um holofote.
uniform float largura = 0.085;

// Inclinação do reflexo, como numa placa de metal pega de viés. É só o
// desenho da faixa que inclina; o deslocamento continua horizontal.
uniform float inclinacao = 0.28;

// Quanto o núcleo clareia a letra.
uniform float forca = 1.0;
uniform vec3 nucleo : source_color = vec3(1.0, 1.0, 1.0);

varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	// A MÁSCARA TEM DUAS PARTES.
	//
	// O alfa do glifo diz onde há letra. A luminância diz onde há a
	// PARTE CLARA da letra — e isso importa porque o letreiro é
	// desenhado com um contorno quase preto por baixo. Sem a segunda
	// parte, a faixa clareava o contorno junto e o brilho voltava a ler
	// como um bloco retangular atravessando o nome.
	float corpo = base.a * smoothstep(0.22, 0.55, max(max(base.r, base.g), base.b));

	float u = (local.x - inicio_x + local.y * inclinacao) / max(extensao_x, 1.0);
	float d = abs(u - posicao);
	// Duas bordas: um núcleo curto e um halo largo em volta dele. Uma
	// borda só dá uma barra com degradê; duas dão um reflexo.
	float halo = 1.0 - smoothstep(largura * 0.30, largura, d);
	float centro = 1.0 - smoothstep(0.0, largura * 0.30, d);
	float brilho = (halo * 0.55 + centro * 0.45) * forca * corpo;

	// A SOMBRA AO REDOR DA FAIXA — sem ela o efeito não existe em letra
	// branca.
	//
	// O núcleo do reflexo é branco, e o PUNCH já é branco: clarear o que
	// está no teto não muda pixel nenhum, e a passagem só aparecia no
	// CHALLENGE dourado. Um reflexo de verdade não é só a luz: é a luz
	// CONTRA o que está em volta. Escurecendo de leve a vizinhança da
	// faixa — e só a vizinhança, nunca a letra inteira — o branco ganha
	// para onde subir, e o brilho passa a ser visto nos dois.
	float vizinhanca = 1.0 - smoothstep(largura, largura * 3.2, d);
	float escurece = clamp(vizinhanca - halo, 0.0, 1.0) * corpo;

	vec3 cor = base.rgb * mix(1.0, 0.82, escurece);
	cor = mix(cor, nucleo, clamp(brilho * 0.9, 0.0, 1.0));
	cor += nucleo * brilho * 0.30;
	COLOR = vec4(cor, base.a);
}
