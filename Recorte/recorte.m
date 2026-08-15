%% Processamento em lote - Region Growing
clc
clear
close all

%% ===== Pastas =====
inputFolder = 'Fotos OAE';
outputFolder = 'Fotos Recortadas';

if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

%% ===== Lista de imagens =====
allFiles = dir(fullfile(inputFolder, '*.*'));
allFiles = allFiles(~[allFiles.isdir]);

extensoesValidas = {'.jpg', '.jpeg', '.png', '.tif', '.tiff', '.bmp'};

manter = false(size(allFiles));

for i = 1:numel(allFiles)
    [~,~,ext] = fileparts(allFiles(i).name);
    manter(i) = ismember(lower(ext), extensoesValidas);
end

files = allFiles(manter);

if isempty(files)
    error('Nenhuma imagem foi encontrada na pasta "%s".', inputFolder);
end

%% ===== Parâmetros gerais =====

% Região ao redor do clique para estimativa inicial da textura
win = 15;

% Tolerância em relação à textura inicial fixa
tolSeed = 0.12;

% Tolerância em relação à textura média adaptativa
tolAdaptive = 0.07;

% Velocidade de atualização da textura adaptativa
% Valores menores tornam T0 mais estável
alpha = 0.01;

% Raio do fechamento morfológico
raioFechamento = 15;

% Percentual máximo da imagem para preenchimento de buracos
percentualBuraco = 0.01;

%% ===== Vizinhança com 8-conectividade =====
neighbors = [-1 -1;
             -1  0;
             -1  1;
              0 -1;
              0  1;
              1 -1;
              1  0;
              1  1];

%% ===== Processamento das imagens =====
for k = 1:length(files)

    %% ===== Leitura =====
    fileName = files(k).name;
    filePath = fullfile(inputFolder, fileName);

    fprintf('Processando %d de %d: %s\n', ...
        k, length(files), fileName);

    I = imread(filePath);

    % Converte imagens em escala de cinza para RGB
    if size(I,3) == 1
        I = repmat(I, [1 1 3]);
    end

    gray = im2double(rgb2gray(I));

    %% ===== Mapa de textura =====
    entropyMap = entropyfilt(gray, true(5));
    entropyMap = mat2gray(entropyMap);

    [h,w] = size(gray);

    %% ===== Seleção do ponto inicial =====
    figure('Name', fileName);
    imshow(I)

    title(sprintf('Clique no PILAR — %s', fileName), ...
        'Interpreter', 'none');

    [x,y] = ginput(1);

    x = round(x);
    y = round(y);

    close

    % Garante que o ponto esteja dentro da imagem
    x = min(max(x,1),w);
    y = min(max(y,1),h);

    %% ===== Consideração 1: textura inicial regional =====

    % Limites da região ao redor do clique
    x1 = max(1, x-win);
    x2 = min(w, x+win);

    y1 = max(1, y-win);
    y2 = min(h, y+win);

    % Região inicial no mapa de textura
    regiaoInicial = entropyMap(y1:y2, x1:x2);

    % Textura inicial fixa
    Tseed = median(regiaoInicial(:));

    % Textura inicialmente adaptativa
    T0 = Tseed;

    %% ===== Inicialização =====
    mask = false(h,w);
    visited = false(h,w);

    % Pré-alocação da fila
    queue = zeros(h*w,2,'uint32');

    head = 1;
    tail = 1;

    queue(tail,:) = [y x];

    mask(y,x) = true;
    visited(y,x) = true;

    %% ===== Region Growing =====
    while head <= tail

        py = double(queue(head,1));
        px = double(queue(head,2));

        head = head + 1;

        for i = 1:8

            ny = py + neighbors(i,1);
            nx = px + neighbors(i,2);

            %% Limites da imagem
            if ny < 1 || ny > h || nx < 1 || nx > w
                continue
            end

            %% Pixel já analisado
            if visited(ny,nx)
                continue
            end

            visited(ny,nx) = true;

            %% Textura do pixel candidato
            val = entropyMap(ny,nx);

            %% Consideração 2: controle de deriva de T0

            % Comparação com a textura inicial fixa
            condicaoSeed = abs(val - Tseed) < tolSeed;

            % Comparação com a textura adaptativa
            condicaoAdaptativa = abs(val - T0) < tolAdaptive;

            % O pixel deve atender aos dois critérios
            if condicaoSeed && condicaoAdaptativa

                mask(ny,nx) = true;

                %% Adiciona o pixel aceito à fila
                tail = tail + 1;
                queue(tail,:) = [ny nx];

                %% Atualização lenta da textura adaptativa
                T0 = (1-alpha)*T0 + alpha*val;
            end
        end
    end

    %% ===== Consideração 7: fechamento menos agressivo =====
    mask = imclose(mask, strel('disk', raioFechamento));

    %% ===== Preenchimento de buracos pequenos =====
    filledMask = imfill(mask, 'holes');

    % Regiões adicionadas pelo preenchimento
    holes = filledMask & ~mask;

    % Área máxima de buraco que pode ser preenchida
    limite = round(numel(gray)*percentualBuraco);

    % Mantém somente os buracos com área igual ou superior ao limite
    holesLarge = bwareaopen(holes, limite);

    % Seleciona os buracos menores que o limite
    holesSmall = holes & ~holesLarge;

    % Preenche apenas os buracos pequenos
    mask = mask | holesSmall;

    %% ===== Resultado =====
    result = I;
    result(repmat(~mask,[1 1 3])) = 0;

    %% ===== Salvar com o mesmo nome =====
    outputPath = fullfile(outputFolder, fileName);
    imwrite(result, outputPath);

    fprintf('Imagem salva em: %s\n', outputPath);
end

disp('Todas as imagens foram processadas e salvas.');
