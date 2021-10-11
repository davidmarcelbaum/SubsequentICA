function [structEEG, lst_changes] = f_load_data(...
    fileName, filePath, dataType)

if strcmp(dataType,'.set')
    
    [structEEG, lst_changes] = ...
        pop_loadset('filename', fileName, ...
        'filepath', filePath);
    
elseif strcmp(dataType,'.mff')
    
    % mff folders contain various files
    [structEEG, lst_changes] = ...
        pop_mffimport([filePath, filesep, fileName], ...
        {'classid' 'code' 'description' 'label' 'mffkey_cidx' ...
        'mffkey_gidx' 'mffkeys' 'mffkeysbackup' 'relativebegintime' ...
        'sourcedevice'});
    
elseif strcmp(dataType,'.cdt')
    
    [structEEG, lst_changes] = ...
        loadcurry([filePath, filesep, fileName], ...
        'CurryLocations', 'False');
    
end

end