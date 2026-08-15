clc; close all; clear;

%% ===== Carregar modelo treinado =====
load('rede_trincas.mat', ...
    'netTransfer', ...
    'dlnet', ...
    'inputSize', ...
    'classNames', ...
    'softmaxName', ...
    'featureLayerName');

disp('Modelo carregado com sucesso!');

%% ===== Caminho da imagem =====
folderPath = "C:\Users\felip\OneDrive\Eng. Civil\IC\O.A.E\2° - Recorte\Fotos Recortadas";
fileName = "DJI_0325.jpg";

imagePath = fullfile(folderPath, fileName);

%% ===== Parâmetros =====
gsd = 0.3;
lado_cm = 50;
overlapFactor = 0.25;

scoreThreshold = 0.45;
gradcamThreshold = 0.3;
alpha = 0.3;

%% ===== NOVO: faixa de exclusão da borda do recorte =====
faixaExclusao_cm = 5;                   % ajuste inicial recomendado
faixaExclusao_px = max(1, round(faixaExclusao_cm / gsd));

% limiar para separar fundo preto do pilar
backgroundThreshold = 10;              % pode ajustar se necessário

%% ===== Cálculo do bloco =====
blockSize = [round(lado_cm / gsd), round(lado_cm / gsd)];
[blockH, blockW] = deal(blockSize(1), blockSize(2));

padH = round(overlapFactor * blockH / 2);
padW = round(overlapFactor * blockW / 2);

%% ===== Leitura da imagem =====
inputImage = imread(imagePath);

if size(inputImage,3) == 1
    inputImage = repmat(inputImage, [1 1 3]);
end

[height, width, ~] = size(inputImage);

%% ===== Máscara do pilar e máscara segura =====

% Considera como pilar os pixels diferentes do fundo escuro
maskPilar = any(inputImage > backgroundThreshold, 3);

%% ===== Limpeza inicial =====

% Fecha pequenas descontinuidades da máscara
maskPilar = imclose(maskPilar, strel('disk', 3));

% Remove pequenas regiões isoladas
minArea = max(50, round(0.001 * height * width));
maskPilar = bwareaopen(maskPilar, minArea);

%% ===== Preencher SOMENTE pequenos buracos =====
% IMPORTANTE:
% Grandes vazios internos do pilar são preservados.

maskPreenchida = imfill(maskPilar, 'holes');

% Identifica todos os buracos existentes
buracos = maskPreenchida & ~maskPilar;

% Identifica cada buraco individualmente
CC = bwconncomp(buracos, 8);

% Área máxima de um buraco que pode ser considerado ruído
%
% Buracos maiores que esse valor são interpretados como
% vazios geométricos reais do pilar.
maxHoleArea_cm2 = 100;   % ajustar se necessário

% Conversão da área real para pixels
maxHoleArea_px = round(maxHoleArea_cm2 / (gsd^2));

% Máscara contendo apenas pequenos buracos
smallHoles = false(size(maskPilar));

for k = 1:CC.NumObjects

    areaHole = numel(CC.PixelIdxList{k});

    if areaHole <= maxHoleArea_px
        smallHoles(CC.PixelIdxList{k}) = true;
    end
end

% Preenche somente os pequenos buracos
maskPilar = maskPilar | smallHoles;

%% ===== Criar margem de segurança =====

% A erosão agora atua:
% 1 - na borda externa do pilar
% 2 - nas bordas dos vazios internos

maskSegura = imerode(maskPilar, ...
    strel('disk', faixaExclusao_px));

%% ===== Verificação =====

if ~any(maskSegura(:))
    error(['A máscara segura ficou vazia. ', ...
        'Reduza o valor de faixaExclusao_cm.']);
end

%% ===== Visualização =====
figure;
imshow(inputImage);
hold on;

% Borda real do pilar, incluindo vazios internos
visboundaries(maskPilar, ...
    'Color', 'y', ...
    'LineWidth', 0.7);

% Limite da área segura
visboundaries(maskSegura, ...
    'Color', 'g', ...
    'LineWidth', 1);

title(sprintf( ...
    'Área segura - exclusão de %.1f cm nas bordas', ...
    faixaExclusao_cm));

hold off;

%% ===== Visualização opcional da máscara segura =====
figure;
imshow(inputImage);
title('Máscara segura aplicada ao pilar');
hold on;
visboundaries(maskPilar, 'Color', 'y', 'LineWidth', 0.5);
visboundaries(maskSegura, 'Color', 'g', 'LineWidth', 1);
legend({'Borda original', 'Região segura'});
hold off;

%% ===== Inicialização =====
nLin = ceil(height / blockH);
nCol = ceil(width / blockW);

matrizAfetada = zeros(nLin, nCol);
recombinedImage = inputImage;

%% ===== Identificar índice da classe "Positive" =====
idxPositive = find(classNames == "Positive");

if isempty(idxPositive)
    error('Classe "Positive" não encontrada no modelo.');
end

%% ===== Loop de análise =====
for i = 1:nLin
    for j = 1:nCol

        % ----- bloco original -----
        rowStart = (i - 1) * blockH + 1;
        colStart = (j - 1) * blockW + 1;
        rowEnd = min(rowStart + blockH - 1, height);
        colEnd = min(colStart + blockW - 1, width);

        originalBlock = inputImage(rowStart:rowEnd, colStart:colEnd, :);
        safeMaskBlock = maskSegura(rowStart:rowEnd, colStart:colEnd);

        % Se o bloco não possui região segura, não analisa
        if ~any(safeMaskBlock(:))
            continue
        end

        % ----- bloco expandido -----
        padRowStart = max(1, rowStart - padH);
        padColStart = max(1, colStart - padW);
        padRowEnd = min(height, rowEnd + padH);
        padColEnd = min(width, colEnd + padW);

        expandedBlock = inputImage(padRowStart:padRowEnd, padColStart:padColEnd, :);
        safeMaskExpanded = maskSegura(padRowStart:padRowEnd, padColStart:padColEnd);

        % ----- NOVO: recortar apenas a região segura para análise -----
        rowsValid = find(any(safeMaskExpanded, 2));
        colsValid = find(any(safeMaskExpanded, 1));

        if isempty(rowsValid) || isempty(colsValid)
            continue
        end

        cropRow1 = rowsValid(1);
        cropRow2 = rowsValid(end);
        cropCol1 = colsValid(1);
        cropCol2 = colsValid(end);

        analysisBlock = expandedBlock(cropRow1:cropRow2, cropCol1:cropCol2, :);

        % coordenadas globais da região realmente analisada
        cropGlobalRowStart = padRowStart + cropRow1 - 1;
        cropGlobalRowEnd   = padRowStart + cropRow2 - 1;
        cropGlobalColStart = padColStart + cropCol1 - 1;
        cropGlobalColEnd   = padColStart + cropCol2 - 1;

        %% ===== Pré-processamento =====
        Istrech = imadjust(analysisBlock, stretchlim(analysisBlock));
        resizedBlock = imresize(Istrech, inputSize(1:2));

        %% ===== Classificação =====
        [label, scores] = classify(netTransfer, resizedBlock);
        positiveScore = scores(idxPositive);

        if positiveScore >= scoreThreshold

            matrizAfetada(i, j) = 1;

            %% ===== Grad-CAM =====
            dlImg = dlarray(single(resizedBlock), 'SSC');

            [featureMap, dScoresdMap] = dlfeval(@gradcam, dlnet, dlImg, ...
                softmaxName, featureLayerName, label);

            gradcamMap = sum(featureMap .* sum(dScoresdMap, [1, 2]), 3);
            gradcamMap = rescale(extractdata(gradcamMap));

            heatmapMask = gradcamMap >= gradcamThreshold;
            heatmapRGB = ind2rgb(im2uint8(gradcamMap), jet(256));
            heatmapRGB(repmat(~heatmapMask, [1 1 3])) = 0;

            % redimensiona o heatmap para a área realmente analisada
            cropH = cropGlobalRowEnd - cropGlobalRowStart + 1;
            cropW = cropGlobalColEnd - cropGlobalColStart + 1;

            heatmapResized = imresize(heatmapRGB, [cropH, cropW]);
            maskResized = imresize(heatmapMask, [cropH, cropW], 'nearest');

            %% ===== Sobreposição apenas na interseção com o bloco original =====
            overlayBlock = im2double(originalBlock);

            ovRowStart = max(rowStart, cropGlobalRowStart);
            ovRowEnd   = min(rowEnd, cropGlobalRowEnd);
            ovColStart = max(colStart, cropGlobalColStart);
            ovColEnd   = min(colEnd, cropGlobalColEnd);

            if ovRowStart <= ovRowEnd && ovColStart <= ovColEnd

                % índices locais no heatmap redimensionado
                heatRows = (ovRowStart - cropGlobalRowStart + 1):(ovRowEnd - cropGlobalRowStart + 1);
                heatCols = (ovColStart - cropGlobalColStart + 1):(ovColEnd - cropGlobalColStart + 1);

                % índices locais no bloco original
                blockRows = (ovRowStart - rowStart + 1):(ovRowEnd - rowStart + 1);
                blockCols = (ovColStart - colStart + 1):(ovColEnd - colStart + 1);

                heatLocal = heatmapResized(heatRows, heatCols, :);
                maskLocalGrad = maskResized(heatRows, heatCols);
                maskLocalSafe = maskSegura(ovRowStart:ovRowEnd, ovColStart:ovColEnd);

                % máscara final: só destaca o que estiver em área segura
                maskFinal = maskLocalGrad & maskLocalSafe;

                for c = 1:3
                    channelOriginal = overlayBlock(blockRows, blockCols, c);
                    channelHeat = heatLocal(:, :, c);

                    channelOriginal(maskFinal) = ...
                        alpha * channelHeat(maskFinal) + ...
                        (1 - alpha) * channelOriginal(maskFinal);

                    overlayBlock(blockRows, blockCols, c) = channelOriginal;
                end
            end

            recombinedImage(rowStart:rowEnd, colStart:colEnd, :) = im2uint8(overlayBlock);
        end
    end
end

%% ===== Exibir resultado =====
figure;
imshow(recombinedImage, []);
title('Grad-CAM + Detecção de Trincas (com exclusão das bordas do recorte)');

%% ===== Salvar imagem =====
outputPath = 'Resultado Detecção';

if ~exist(outputPath, 'dir')
    mkdir(outputPath);
end

fileList = dir(fullfile(outputPath, '*.jpg'));
numeros = [];

for k = 1:length(fileList)
    [~, name, ~] = fileparts(fileList(k).name);
    num = str2double(name);
    if ~isnan(num)
        numeros = [numeros, num];
    end
end

if isempty(numeros)
    novoNumero = 1;
else
    novoNumero = max(numeros) + 1;
end

fileNameOut = sprintf('%04d.jpg', novoNumero);
imwrite(recombinedImage, fullfile(outputPath, fileNameOut));

disp(['Imagem salva: ' fullfile(outputPath, fileNameOut)]);

%% ===== Grad-CAM =====
function [featureMap,dScoresdMap] = gradcam(dlnet, dlImg, softmaxName, featureLayerName, classfn)
    [scores,featureMap] = predict(dlnet, dlImg, ...
        'Outputs', {softmaxName, featureLayerName});
    
    classScore = scores(classfn);
    dScoresdMap = dlgradient(classScore, featureMap);
end

%% ===== Matriz visual =====
function MatrizIA(matriz, lado_cm, gsd, outputFileName)

    quadSize = round(lado_cm / gsd);
    separador = 8;

    [nLin, nCol] = size(matriz);

    altura = nLin * quadSize + (nLin - 1) * separador;
    largura = nCol * quadSize + (nCol - 1) * separador;

    img = uint8(255 * ones(altura, largura, 3));

    for i = 1:nLin
        for j = 1:nCol

            rowStart = (i-1) * (quadSize + separador) + 1;
            rowEnd = rowStart + quadSize - 1;

            colStart = (j-1) * (quadSize + separador) + 1;
            colEnd = colStart + quadSize - 1;

            if matriz(i,j) == 1
                cor = uint8(cat(3, 255*ones(quadSize), zeros(quadSize), zeros(quadSize)));
            else
                cor = uint8(cat(3, zeros(quadSize), zeros(quadSize), 255*ones(quadSize)));
            end

            img(rowStart:rowEnd, colStart:colEnd, :) = cor;
        end
    end

    imwrite(img, outputFileName);

    figure;
    imshow(img);
    title('Matriz de Trincas');

    outputPathM = 'Resultado Partic_calor\Matriz';

    if ~exist(outputPathM, 'dir')
        mkdir(outputPathM);
    end

    [~, nameWithoutExt, ~] = fileparts(outputFileName);
    save(fullfile(outputPathM, [nameWithoutExt '.mat']), 'matriz');
end
