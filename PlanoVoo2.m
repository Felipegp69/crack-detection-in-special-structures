clc; clear;
%% ===============================
% 1. Leitura da planilha
% ===============================
nomeExcel = 'P1 Esquerda.xlsx';
dados = readcell(nomeExcel);

lat       = str2double(dados(2:31,2));
lon       = str2double(dados(2:31,3));
alt       = str2double(dados(2:31,4));
vel       = dados(2:31,5);
yaw0      = dados(2:31,6);
gimbal0   = dados(2:31,7);
distAcoes = str2double(dados(2:31,8));

acoesTxt = dados(2:31,[9 11 13 15]);

params = nan(size(acoesTxt));
colParams = [10 12 14 16];
for k = 1:length(colParams)
    if colParams(k) <= size(dados,2)
        params(:,k) = str2double(dados(2:31,colParams(k)));
    end
end

idxValidos = ~isnan(lat) & ~isnan(lon);

lat      = lat(idxValidos);
lon      = lon(idxValidos);
alt      = alt(idxValidos);
vel      = vel(idxValidos);
yaw0     = yaw0(idxValidos);
gimbal0  = gimbal0(idxValidos);
distAcoes = distAcoes(idxValidos);
acoesTxt = acoesTxt(idxValidos,:);
params   = params(idxValidos,:);

nWP = numel(lat);

%% ===============================
% 2. Construção dos waypoints (com secundários)
% ===============================

LAT = lat(1);
LON = lon(1);
ALT = alt(1);
VEL = vel(1);
YAW = yaw0(1);
GIM = gimbal0(1);
IS_PRINC = true;

IDX_PRINC = 1;

for i = 1:nWP-1
    % adiciona waypoint principal i
    if i > 1
        LAT(end+1) = lat(i);
        LON(end+1) = lon(i);
        ALT(end+1) = alt(i);
        VEL(end+1) = vel(i);
        YAW(end+1) = yaw0(i);
        GIM(end+1) = gimbal0(i);
        IS_PRINC(end+1) = true;
        IDX_PRINC(end+1) = i;
    end

    % distância aproximada em metros
    dLat = (lat(i+1) - lat(i)) * 111320;
    dLon = (lon(i+1) - lon(i)) * 111320 * cosd(lat(i));
    distTotal = hypot(dLat, dLon);

    dA = distAcoes(i);
    if isnan(dA) || dA <= 0
        continue
    end

    nSec = floor(distTotal / dA) - 1;
    if nSec < 1
        continue
    end

    for k = 1:nSec
        t = k / (nSec + 1);
        LAT(end+1) = lat(i) + t*(lat(i+1)-lat(i));
        LON(end+1) = lon(i) + t*(lon(i+1)-lon(i));
        ALT(end+1) = alt(i) + t*(alt(i+1)-alt(i));
        VEL(end+1) = vel(i);
        YAW(end+1) = yaw0(i);
        GIM(end+1) = gimbal0(i);
        IS_PRINC(end+1) = false;
        IDX_PRINC(end+1) = i;
    end
end

% último waypoint principal
LAT(end+1) = lat(end);
LON(end+1) = lon(end);
ALT(end+1) = alt(end);
VEL(end+1) = vel(end);
YAW(end+1) = yaw0(end);
GIM(end+1) = gimbal0(end);
IS_PRINC(end+1) = true;
IDX_PRINC(end+1) = nWP;

nALL = numel(LAT);

%% ===============================
% 3. Arquivo KML
% ===============================
[~,nomeBase,~] = fileparts(nomeExcel);
fid = fopen([nomeBase '.kml'],'w');

fprintf(fid,'<?xml version="1.0" encoding="UTF-8"?>\n');
fprintf(fid,'<kml xmlns="http://www.opengis.net/kml/2.2">\n');
fprintf(fid,'<Document xmlns="">\n');
fprintf(fid,'<name>%s</name>\n',nomeBase);
fprintf(fid,'<open>1</open>\n');
fprintf(fid,'<ExtendedData xmlns:mis="www.dji.com">\n');
fprintf(fid,'<mis:type>Waypoint</mis:type>\n');
fprintf(fid,'<mis:stationType>0</mis:stationType>\n');
fprintf(fid,'</ExtendedData>\n');
%% ===== Styles (obrigatórios para fidelidade DJI) =====
fprintf(fid,'<Style id="waylineGreenPoly">\n');
fprintf(fid,'<LineStyle><color>FF0AEE8B</color><width>6</width></LineStyle>\n');
fprintf(fid,'</Style>\n');
fprintf(fid,'<Style id="waypointStyle">\n');
fprintf(fid,'<IconStyle><Icon>\n');
fprintf(fid,'<href>https://cdnen.dji-flighthub.com/static/app/images/point.png</href>\n');
fprintf(fid,'</Icon></IconStyle>\n');
fprintf(fid,'</Style>\n');

%% ===============================
% 4. Waypoints
% ===============================

fprintf(fid,'<Folder>\n');
fprintf(fid,'<name>Waypoints</name>\n');
fprintf(fid,'<description>Waypoints in the Mission.</description>\n');

wpID = 1;

for i = 1:nALL
    fprintf(fid,'<Placemark>\n');
    fprintf(fid,'<name>Waypoint%d</name>\n',i);
    fprintf(fid,'<visibility>1</visibility>\n');
    fprintf(fid,'<description>Waypoint</description>\n');
    fprintf(fid,'<styleUrl>#waypointStyle</styleUrl>\n');

    fprintf(fid,'<ExtendedData xmlns:mis="www.dji.com">\n');
    fprintf(fid,'<mis:useWaylineAltitude>false</mis:useWaylineAltitude>\n');
    fprintf(fid,'<mis:heading>%d</mis:heading>\n',round(YAW{i}));
    fprintf(fid,'<mis:turnMode>Auto</mis:turnMode>\n');
    fprintf(fid,'<mis:gimbalPitch>%.1f</mis:gimbalPitch>\n',GIM{i});

    fprintf(fid,'<mis:useWaylineSpeed>false</mis:useWaylineSpeed>\n');
    fprintf(fid,'<mis:speed>%.1f</mis:speed>\n',VEL{i});

    fprintf(fid,'<mis:useWaylineHeadingMode>true</mis:useWaylineHeadingMode>\n');
    fprintf(fid,'<mis:useWaylinePointType>true</mis:useWaylinePointType>\n');
    fprintf(fid,'<mis:pointType>LineStop</mis:pointType>\n');
    fprintf(fid,'<mis:cornerRadius>0.2</mis:cornerRadius>\n');

    % ações SOMENTE em principais
    
        ip = IDX_PRINC(i);
        for a = 1:size(acoesTxt,2)
            acao = string(acoesTxt{ip,a});
            if acao == "" || ismissing(acao), continue; end

            switch lower(acao)
                case "foto"
                   fprintf(fid,'<mis:actions param="0" accuracy="0" cameraIndex="0" payloadType="0" payloadIndex="0">ShootPhoto</mis:actions>\n');
                case "rotação drone"
                    par = params(ip,a);
                    if ~isnan(par)
                        fprintf(fid,'<mis:actions param="%d" accuracy="0" cameraIndex="0" payloadType="0" payloadIndex="0">AircraftYaw</mis:actions>\n',par);
                    end
                case "rotação gimbal"
                    par = params(ip,a);
                    if ~isnan(par)
                        fprintf(fid, '<mis:actions param="%d" accuracy="1" cameraIndex="0" payloadType="0" payloadIndex="0">GimbalPitch</mis:actions>\n',par);
                    end
            end
        end
    

    fprintf(fid,'</ExtendedData>\n');
    fprintf(fid,'<Point>\n');
    fprintf(fid,'<altitudeMode>relativeToGround</altitudeMode>\n');
    fprintf(fid,'<coordinates>%.6f,%.6f,%.1f</coordinates>\n',LON(i),LAT(i),ALT(i));
    fprintf(fid,'</Point>\n');
    fprintf(fid,'</Placemark>\n');

    wpID = wpID + 1;
end

fprintf(fid,'</Folder>\n');

%% ===============================
% 5. Wayline
% ===============================

fprintf(fid,'<Placemark>\n');
fprintf(fid,'<name>Wayline</name>\n');
fprintf(fid,'<description>Wayline</description>\n');
fprintf(fid,'<visibility>1</visibility>\n');

fprintf(fid,'<ExtendedData xmlns:mis="www.dji.com">\n');
fprintf(fid,'<mis:altitude>50.0</mis:altitude>\n');
fprintf(fid,'<mis:autoFlightSpeed>%.1f</mis:autoFlightSpeed>\n',VEL{1});
fprintf(fid,'<mis:actionOnFinish>GoHome</mis:actionOnFinish>\n');
fprintf(fid,'<mis:headingMode>UsePointSetting</mis:headingMode>\n');
fprintf(fid,'<mis:gimbalPitchMode>UsePointSetting</mis:gimbalPitchMode>\n');
fprintf(fid,'<mis:powerSaveMode>false</mis:powerSaveMode>\n');
fprintf(fid,'<mis:waypointType>LineStop</mis:waypointType>\n');

fprintf(fid,'<mis:droneInfo>\n');
% fprintf(fid,'<mis:droneType>COMMON</mis:droneType>\n');                  Drones gerais
fprintf(fid,'<mis:droneType>P4R</mis:droneType>\n');                       %Phanton RTK 
fprintf(fid,'<mis:advanceSettings>false</mis:advanceSettings>\n');
fprintf(fid,'<mis:droneCameras/>\n');
fprintf(fid,'<mis:droneHeight>\n');
fprintf(fid,'<mis:useAbsolute>false</mis:useAbsolute>\n');
fprintf(fid,'<mis:hasTakeoffHeight>false</mis:hasTakeoffHeight>\n');
fprintf(fid,'<mis:takeoffHeight>0.0</mis:takeoffHeight>\n');
fprintf(fid,'</mis:droneHeight>\n');
fprintf(fid,'</mis:droneInfo>\n');

fprintf(fid,'</ExtendedData>\n');

fprintf(fid,'<styleUrl>#waylineGreenPoly</styleUrl>\n');
fprintf(fid,'<LineString>\n');
fprintf(fid,'<tessellate>1</tessellate>\n');
fprintf(fid,'<altitudeMode>relativeToGround</altitudeMode>\n');
fprintf(fid,'<coordinates>');

for i = 1:nALL
    fprintf(fid,'%.6f,%.6f,%.1f ',LON(i),LAT(i),ALT(i));
end

fprintf(fid,'</coordinates>\n');
fprintf(fid,'</LineString>\n');
fprintf(fid,'</Placemark>\n');
fprintf(fid,'</Document>\n</kml>\n');

fclose(fid);

fprintf('KML gerado com sucesso: %s.kml\n',nomeBase);
