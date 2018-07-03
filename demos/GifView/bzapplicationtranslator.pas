unit BZApplicationTranslator;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, dialogs
  {$IFDEF windows}
  , Windows
  {$ELSE}
  , Unix
    {$IFDEF LCLCarbon}
  , MacOSAll
    {$ENDIF}
  {$ENDIF};

type

  { TBZApplicationTranslator }
  TBZOnTranslateEvent = procedure(Sender : TObject; Const Folder, Lang, FallbackLang: String ) of Object;
  TBZApplicationTranslator = Class
  strict private
    FLanguageApplicationFileName : String;
    FLanguage : String;
    FDefaultLanguage : String;
    FUseSystemLanguage : Boolean;
    FSystemLanguage : String;
    FPathToApp : String;
    FLanguageFileDir : String;

    FOnTranslate : TBZOnTranslateEvent;
    FOnNeedRestartApplication : TNotifyEvent;

    function GetDefaultLanguage: String;
    function GetLanguageApplicationFileName: String;
    function GetSystemLanguage: string;

    procedure SetDefaultLanguage(AValue: String);
    procedure SetLanguage(AValue: String);
    procedure SetLanguageApplicationFileName(AValue: String);
    procedure SetLanguageFileDir(AValue: String);
    procedure SetUseSystemLanguage(AValue: Boolean);

  protected
    function GetApplicationPath : String;
  public
    constructor Create;

    procedure Run;
    procedure Translate; overload;
    procedure Translate(anUnitName:String); overload;
    procedure RestartApplication;

    property SystemLanguage : String Read GetSystemLanguage;
    property ApplicationPath: String Read GetApplicationPath;
  published
    property Language : String read FLanguage write SetLanguage;
    property LanguageFileDir : String read FLanguageFileDir write SetLanguageFileDir;
    property LanguageFileName : String read GetLanguageApplicationFileName write SetLanguageApplicationFileName;
    property DefaultLanguage : String read GetDefaultLanguage write SetDefaultLanguage;
    property UseSystemLanguage : Boolean read FUseSystemLanguage write SetUseSystemLanguage;

    property OnTranslate : TBZOnTranslateEvent Read FOnTranslate Write FOnTranslate;
    //property OnNeedRestartApplication : TNotifyEvent Read FOnNeedRestartApplication write FOnNeedRestartApplication;
  end;

implementation

uses
  UTF8Process,
  FileUtil,
  LazUTF8, LazFileUtils,
  LCLTranslator,
  GetText,
  LResources,
  Translations;

const
  cDefaultLanguageDir  = 'languages';
  cPoExtension         = 'po';
  cDefaultAutoLanguage = 'auto';
  cDefaultLanguage     = 'fr';

{%region=====[ TBZApplicationTranslator ]=======================================}

function TBZApplicationTranslator.GetDefaultLanguage: String;
// *** Retourne le language par defaut choisi: Si "auto" retourne la langue de l'OS sinon la langue par defaut ***
// *** Return the chosen default languge. If "auto" then return OS language else default langage ***
begin
  Result := '';
  if (FUseSystemLanguage) or (LowerCase(FDefaultLanguage) = cDefaultAutoLanguage )  then
    Result := GetSystemLanguage;
  if result = '' then Result := cDefaultLanguage
  else result := FDefaultLanguage;
end;

function TBZApplicationTranslator.GetLanguageApplicationFileName: String;
begin
  Result := FLanguageApplicationFileName;
end;

function TBZApplicationTranslator.GetSystemLanguage: string;
// *** methode independante de la plateform pour lire la langue de l'interface de l'utilisateur ***
// *** platform-independent method to read the language of the user interface ***
var
  l, fbl: string;
  {$IFDEF LCLCarbon}
  theLocaleRef: CFLocaleRef;
  locale: CFStringRef;
  buffer: StringPtr;
  bufferSize: CFIndex;
  encoding: CFStringEncoding;
  success: boolean;
  {$ENDIF}
begin
  {$IFDEF LCLCarbon}
  theLocaleRef := CFLocaleCopyCurrent;
  locale := CFLocaleGetIdentifier(theLocaleRef);
  encoding := 0;
  bufferSize := 256;
  buffer := new(StringPtr);
  success := CFStringGetPascalString(locale, buffer, bufferSize, encoding);
  if success then
    l := string(buffer^)
  else
    l := '';
  fbl := Copy(l, 1, 2);
  dispose(buffer);
  {$ELSE}
    {$IFDEF LINUX}
    fbl := Copy(GetEnvironmentVariableUTF8('LC_CTYPE'), 1, 2);
    if fb='' then fbl := Copy(GetEnvironmentVariableUTF8('LANG'), 1, 2);
    if fb='' then fb:= 'en';
    {$ELSE}
        GetLanguageIDs(l, fbl);
    {$ENDIF}
  {$ENDIF}
  Result := fbl;
end;

procedure TBZApplicationTranslator.SetDefaultLanguage(AValue: String);
// *** Définit le language par defaut. Si "auto" la langue du systeme sera utilisée ***
// *** Define the default language. If "auto" then the sytem's language will be used ***
begin
  FDefaultLanguage := LowerCase(AValue);
end;

procedure TBZApplicationTranslator.SetLanguage(AValue: String);
// *** Definit la langue actuelle utilisée. Si "auto" la langue par defaut est utilisée ***
// *** Define the actual used language. If "auto" then the default language is used ***
begin
  if (AValue = '') then FLanguage := cDefaultLanguage
  else if (AValue = cDefaultAutoLanguage) then FLanguage := DefaultLanguage
  else FLanguage := LowerCase(AValue);
end;

procedure TBZApplicationTranslator.SetLanguageApplicationFileName(AValue: String);
// *** Definit le nom de fichier de traduction pour l'application ***
// *** Define the file name of tanslation file for the application ***
begin
  if AValue <> '' then // pas valeur par défaut ?
    FLanguageApplicationFileName := ExtractFileName(AValue)  // à partir de l'extraction du nom du fichier
  else
    FLanguageApplicationFileName := ExtractFileNameOnly(Application.ExeName);  // à partir du nom du programme
end;

procedure TBZApplicationTranslator.SetLanguageFileDir(AValue: String);
// *** Definit le chemin vers les fichiers de traduction, relatif au dossier de l'application ***
// *** Define the relative path where the translation files are stored from application's folder  ***
begin
  FLanguageFileDir := AValue;
  if FLanguageFileDir <> '' then
    FLanguageFileDir := ExtractFilePath(FLanguageFileDir);
  if FLanguageFileDir = '' then FLanguageFileDir := cDefaultLanguageDir;
end;

procedure TBZApplicationTranslator.SetUseSystemLanguage(AValue: Boolean);
// *** Definit si on doit utiliser la langue du systeme ***
// *** Define if we need to use system'languge ***
begin
  if AValue then
  begin
    FLanguage := cDefaultAutoLanguage;
    FDefaultLanguage := cDefaultAutoLanguage;
  end;
  FUseSystemLanguage := AValue;
end;

function TBZApplicationTranslator.GetApplicationPath: String;
// *** Retourne le chemin complet absolu de l'application ***
// *** Return the absolute path of the application ***
Var
  PathToApp : String;
begin
  {$ifdef windows}
    PathToApp  :=  Copy(Application.ExeName, 1, Pos(ApplicationName + '.exe', Application.ExeName) - 1);
  {$else}
    {$ifdef Linux}
      PathToApp := Copy(Application.ExeName, 1, Pos(ApplicationName, Application.ExeName) - 1);
    {$endif}
    {$ifdef darwin}
      PathToApp := Copy(Application.ExeName, 1, Pos(ApplicationName + '.app', Application.ExeName) - 1);
    {$endif}
  {$endif}
  Result := PathToApp;
end;

constructor TBZApplicationTranslator.Create;
// *** Construction du composant ***
// *** Construction of component ***
begin
  inherited Create;
  UseSystemLanguage := False;
  Language := '';
  DefaultLanguage := cDefaultLanguage;
  LanguageFileName := '';
  LanguageFileDir := '';
end;

procedure TBZApplicationTranslator.Run;
begin
  if Application.ParamCount > 0 then // au moins un paramètre ?
    Language := Application.Params[1] // c'est l'identifiant de la langue
  else
    Language := DefaultLanguage; // langue par défaut

  if Application.ParamCount > 1 then // au moins deux paramètres ?
    LanguageFileDir := Application.Params[2] // c'est le répertoire des fichiers
  else
    LanguageFileDir := ''; // répertoire par défaut

  if Application.ParamCount > 2 then // au moins trois paramètres ?
    LanguageFileName := Application.Params[3] // c'est le nom du fichier
  else
    LanguageFileName := ''; // fichier par défaut

  Translate;
end;

procedure TBZApplicationTranslator.Translate;
// *** Traduction de l'application ***
// *** Translation of the application ***
Var
  LF : String;
  PathToLangFiles : String;
begin
  PathToLangFiles := GetApplicationPath + LanguageFileDir + PathDelim;
  LF := PathToLangFiles + LanguageFileName + '.' + Language + '.' + cPoExtension;
  if FileExistsUTF8(LF) then
  begin
    SetDefaultLang(Language, PathToLangFiles); // On traduit
  end
  else
  begin
    Language := DefaultLanguage; // langue par défaut si erreur
    // On traduit la LCL
    LF := PathToLangFiles + 'lclstrconsts' + '.' + Language + '.' + cPoExtension;
    if FileExistsUTF8(LF) then // existe-t-il ?
      Translations.TranslateUnitResourceStrings('LCLStrConsts', LF,Language, UpperCase(Language)); // on traduit
  end;
  if Assigned(FOnTranslate) then FOnTranslate(Self, LanguageFileDir, Language, UpperCase(Language));
end;

procedure TBZApplicationTranslator.Translate(anUnitName: String);
// *** Traduction des "resourcestrings" présentes dans une unité ***
// *** Translation of the "resourcestrings" in an unit ***
var
  LF : String;
begin
  LF := GetApplicationPath + LanguageFileDir + PathDelim + anUnitName + '.'+Language + '.' + cPoExtension;
  if FileExistsUTF8(LF) then // existe-t-il ?
  begin
    Translations.TranslateUnitResourceStrings(anUnitName,LF);// Language, UpperCase(Language)); // on traduit
  end;
end;

procedure TBZApplicationTranslator.RestartApplication;
// *** Redemmare l'application pour la traduction vers une nouvelle langue ***
// *** Restart the application for translation to a new language ***
var Exe: TProcessUTF8;
begin
  Exe := TProcessUTF8.Create(nil); // processus créé
  try
    Exe.Executable := Application.ExeName; // il porte le nom de l'application
    // ajout des paramètres
    Exe.Parameters.Add(Language);        // langue en paramètre
    Exe.Parameters.Add(LanguageFileDir); // répertoire
    Exe.Parameters.Add(LanguageFileName);        // nom de fichier
    Exe.Execute; // on démarre la nouvelle application
  finally
    Exe.Free; // processus libéré
    Application.Terminate; // l'ancienne application est terminée
  end;
end;

{%endregion}

end.


