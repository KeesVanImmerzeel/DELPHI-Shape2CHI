unit uShape2CHI;

interface

uses
  Windows, Forms, SysUtils, StdCtrls, Controls, Classes,
  Vcl.ExtCtrls, Vcl.Dialogs, uError, ShpAPI129;

type
  TMainForm = class(TForm)
    LabeledEditShapeName: TLabeledEdit;
    OpenDialogShapeFile: TOpenDialog;
    ReadShapeButton: TButton;
    SaveDialogCHIfile: TSaveDialog;
    ListBoxWellCode: TListBox;
    Label1: TLabel;
    ListBoxCluster: TListBox;
    Label2: TLabel;
    ListBoxAquifer: TListBox;
    Label3: TLabel;
    ListBoxMeasured: TListBox;
    Label4: TLabel;
    ListBoxWeight: TListBox;
    Label5: TLabel;
    CreateCHIButton: TButton;
    procedure FormCreate(Sender: TObject);
    procedure LabeledEditShapeNameClick(Sender: TObject);
    procedure ReadShapeButtonClick(Sender: TObject);
    procedure CreateCHIButtonClick(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  MainForm: TMainForm;

Type
  ENot_a_Point_Shape = class( Exception );
  Input_shape_DoesNotExist = class( Exception );

ResourceString
  sNot_a_Point_Shape = 'File [%s] is not a POINT shape.';
  sInput_shape_DoesNotExist =  'Input (point) shape [%s] does not exist.';

implementation
{$R *.DFM}

Type
  TDBFieldname = array[0..12] of AnsiChar;
  TPtrDBFieldname = ^TDBFieldname;
  TCHIrecord = record
    WellCode: String;
    Cluster, Aquifer: Integer;
    Measured, Weight: Double;
  end;

const
  cIni_Files = 'FILES';
  cIni_InputShapeFileName = 'InputShape';
  cIni_OutputFileName = 'OutputFileName';
  cIni_Selection = 'SELECTION';
  cIni_ListBoxWellCode = 'WellCode';
  cIni_ListBoxCluster = 'Cluster';
  cIni_ListBoxAquifer = 'Aquifer';
  cIni_ListBoxMeasured = 'Measured';
  cIni_ListBoxWeight = 'Weight';
  cNrOfItemsToSet = 5;

procedure TMainForm.CreateCHIButtonClick(Sender: TObject);
const
  cWellCode = 0;
  cCluster = 1;
  cAquifer = 2;
  cMeasured = 3;
  cWeight = 4;
var
  i, k, ItemsSet: Integer;
  S, HeaderStr: String;
  sx, sy: Single;
  hSHPHandle:  SHPHandle;
  hDBFHandle:  DBFHandle;
  psShape   :  PSHPObject;
  j, FieldCount, DBRecordCount, aLongIntValue: LongInt;
  ColumNr: Array[0..cNrOfItemsToSet-1] of LongInt;
  PnWidth, PnDecimals: PLongInt;
  FieldType: DBFFieldType;
  PDBFieldName: TPtrDBFieldname;
  S_Ansi: AnsiString;
  SelectedNames: TStringList;
  aCHIrecord: TCHIrecord;
  XStr, YStr, MeasuredStr, WeightStr, WellCodeStr: String[10];
  ClusterStr, AquiferStr: String[5];
  f: TextFile;

  Function IsSelectedField( const aString: String ): Boolean;
  var
    i: Integer;
  begin
    Result := false;
    for i:= 0 to SelectedNames.Count-1 do begin
      if SelectedNames[ i ] = aString then begin
        Result := true;
        Exit;
      end;
    end;
  end;

  Function ClusterNrInRecord( const i: Integer ): Integer;
  Var
    j: LongInt;
  begin
    Result := -1;
    for j:=0 to FieldCount-1 do begin
      FieldType := DBFGetFieldInfo ( hDBFHandle, j, PAnsiCHAR( PDBFieldName ), PnWidth, PnDecimals );
      if ( PDBFieldName  <> nil ) and ( PnWidth <> nil ) and ( PDBFieldName^ = ' ' ) then begin
        aLongIntValue := DBFReadIntegerAttribute( hDBFHandle, i, j );
        Result := aLongIntValue;
      end; {-if}
    end; {-for j}
  end;

begin
  Try
  Try

//  Verzamel de geselecteerde veld namen in TStringList "SelectedNames"
    SelectedNames := TStringList.Create;
    ItemsSet := 0;
    with MainForm do begin
      for i:=0 to ComponentCount-1 do begin
        if Components[ i ] is TListBox  then begin
          with Components[ i ] as TListbox do begin
            if ItemIndex <> -1 then begin
              Inc( ItemsSet );
              SelectedNames.Add( Items[ itemindex ] );
              Writeln(  'Selected Name = ', SelectedNames.Create[ SelectedNames.Count-1 ]  );
            end;
            with fini do
              WriteInteger( cIni_Selection, Name, ItemIndex );
          end;
        end;
      end;
    end;
    if not ( ItemsSet = cNrOfItemsToSet )  then
      raise Exception.Create('Not all items are set');

    with SaveDialogCHIfile do begin
      S := fini.ReadString( cIni_Files, cIni_OutputFileName, '' );
      if FileExists( S ) then begin
        FileName := S;
        ChDir( ExtractFileDir( FileName ) );
      end;
      if Execute then begin
        fini.WriteString( cIni_Files, cIni_OutputFileName, ExpandFileName( FileName ) );

        AssignFile( f, FileName ); Rewrite( f );

        {-Create handle to input shape}
        if ( not FileExists( ChangeFileExt( LabeledEditShapeName.Text, '.shp' ) ) ) then
          Raise Exception.CreateResFmt( @sInput_shape_DoesNotExist, [ExpandFileName( LabeledEditShapeName.Text ) ] );
        Writeln(  'Opening Point Shape [' + LabeledEditShapeName.Text + ']' );
        S_Ansi := AnsiString( LabeledEditShapeName.Text );
        hSHPHandle := SHPOpen ( PAnsiChar( S_Ansi ), PAnsiChar( 'rb' ) );
        S_Ansi := AnsiString( LabeledEditShapeName.Text );

        {-Create handle to dBase file}
        hDBFHandle := DBFOpen(  PAnsiChar( S_Ansi ), PAnsiChar( 'rb' ) );
        FieldCount := DBFGetFieldCount( hDBFHandle );
        DBRecordCount := DBFGetRecordCount ( hDBFHandle );
//        Writeln(  'FieldCount = ', FieldCount );

        {-Zoek de kolomnummers "ColumNr[]" op bij de verschillende geselecteerde velden}
        {-Schrijf de geselecteerde velden naar de log-file}
        New( PnWidth ); New( PnDecimals ); New( PDBFieldName );
        Writeln(  'Velden');
        for j:=0 to FieldCount-1 do begin
          FieldType := DBFGetFieldInfo ( hDBFHandle, j, PAnsiCHAR( PDBFieldName ), PnWidth, PnDecimals );
          if ( PDBFieldName  <> nil ) then begin
            WriteToLogFile_No_CR(   PDBFieldName^ );
            if IsSelectedField( PDBFieldName^ ) then begin
              {-Bewaar kolomnr j bij dit veld}
              for k:=0 to cNrOfItemsToSet-1 do begin
                if PDBFieldName^ = SelectedNames[ k ] then
                  ColumNr[ k ] := j;
              end;
              WriteToLogFileFmt ( ' = SELECTED FIELD in columnr %d', [j+1] );
            end else
              WriteToLogFile(  ' = NOT SELECTED FIELD' );
          end else
            WriteToLogFile_No_CR( 'nilFieldName = ' );
        end;

        {-Schrijf kopregel}
        HeaderStr := 'Meetpunt    x         y         Clust  WVP     gws     Time      gewicht';
        Writeln(  HeaderStr  );
        Writeln( f, HeaderSTr );

        {-Schrijf de records van de geselecteerde velden als Clusternr > 0 }
        for i:= 0 to DBRecordCount-1 do begin
//        {-Lees aCHIrecord }
          with aChiRecord do begin
            WellCode := ''; Aquifer := -999; Measured := -999; Weight := -999;
            {-ClusterNr}
            Cluster := DBFReadIntegerAttribute( hDBFHandle, i, ColumNr[ cCluster ] );
            if Cluster > 0 then begin {-Lees alleen record verder als clusternr > 0}
              WellCode := DBFReadStringAttribute (hDBFHandle, i, ColumNr[ cWellCode ] );
              Aquifer  := DBFReadIntegerAttribute( hDBFHandle, i, ColumNr[ cAquifer ] );
              Measured := DBFReadDoubleAttribute ( hDBFHandle, i, ColumNr[ cMeasured ] );
              FieldType := DBFGetFieldInfo ( hDBFHandle, ColumNr[ cWeight ], PAnsiCHAR( PDBFieldName ), PnWidth, PnDecimals );
              if ( FieldType = FTInteger ) then
                Weight := DBFReadIntegerAttribute( hDBFHandle, i, ColumNr[ cWeight ] )
              else
                Weight := DBFReadDoubleAttribute ( hDBFHandle, i, ColumNr[ cWeight ] );
            end;
          end; {-with}
          {-Lees xy coordinaten en schrijf record als Cluster > 0}
          with aChiRecord do begin
            if Cluster > 0 then begin
              psShape := SHPReadObject ( hSHPHandle, i );
              with psShape^ do begin
                sx := padfX[0];
                sy := padfY[ 0 ];
              end; {-with}
              SHPDestroyObject( psShape );
              WellCodeStr := WellCode;
              Str( sx:10:0, XStr ); Str( sy:10:0, YStr );
              ClusterStr := Format('%5d', [Cluster] );
              AquiferStr := Format('%5d', [Aquifer] );
              Str( Measured:10:2, MeasuredStr );
              Str( Weight:10:2, WeightStr );
              for j := Length( WellCodeStr )-1 to 9 do
                WellCodeStr := WellCodeStr + ' ';
              S := WellCodeStr + XStr + YStr + ClusterStr + AquiferStr + MeasuredStr + '          ' + WeightStr;
              Writeln(  S );
              Writeln( f, S );
            end;
          end;
        end; {-for i}

        SHPClose( hSHPHandle );
        DBFClose( hDBFHandle );

        CreateCHIButton.Visible := false;
        ReadShapeButton.Visible := true;

        CloseFile( f );

      end; {-If Execute}
    end; {-with SaveDialogCHIfile}


  Except
    On E: Exception do begin
      HandleError( E.Message, true );
      MessageBeep( MB_ICONASTERISK );
    end;
  End;
  Finally

  End;
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  S: String;
begin
  InitialiseLogFile;
  Caption :=  ChangeFileExt( ExtractFileName( Application.ExeName ), '' );
  with fini do begin
    S := ReadString( cIni_Files, cIni_InputShapeFileName, '' );
    if FileExists( S ) then LabeledEditShapeName.Text := ExpandFileName( S );
  end;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
FinaliseLogFile;
end;

procedure TMainForm.ReadShapeButtonClick(Sender: TObject);
var
  S: String;

  Var
    hSHPHandle:  SHPHandle;
    hDBFHandle:  DBFHandle;
    ShapeInfo:  SHPInfo;
    i, j, FieldCount, DBRecordCount: LongInt;
    PnWidth, PnDecimals: PLongInt;
    FieldType: DBFFieldType;
    PDBFieldName: TPtrDBFieldname;
    S_Ansi: AnsiString;

begin
  with SaveDialogCHIfile do begin
    {-clear listboxes}
    with MainForm do begin
      for i:=0 to ComponentCount-1 do begin
        if Components[ i ] is TListBox  then begin
          with Components[ i ] as TListbox do begin
            Clear;
          end;
        end;
      end;
    end;

    S := fini.ReadString( cIni_Files, cIni_OutputFileName, '' );
    if FileExists( S ) then begin
      FileName := S;
    end;
    if {Execute} true then begin
      Try
      Try
        fini.WriteString( cIni_Files, cIni_OutputFileName, ExpandFileName( FileName ) );

        {-Create handle to input shape}
        if ( not FileExists( ChangeFileExt( LabeledEditShapeName.Text, '.shp' ) ) ) then
          Raise Exception.CreateResFmt( @sInput_shape_DoesNotExist, [ExpandFileName( LabeledEditShapeName.Text ) ] );
        Writeln(  'Opening Point Shape [' + LabeledEditShapeName.Text + ']' );

        S_Ansi := AnsiString( LabeledEditShapeName.Text );
        hSHPHandle := SHPOpen ( PAnsiChar( S_Ansi ), PAnsiChar( 'rb' ) );

        {-Extract and dump input shape properties}
        with ShapeInfo do begin
          SHPGetInfo ( hSHPHandle, @nRecords, @nShapeType, @adBoundsMin, @adBoundsMax );
          Writeln(  'nr. records: ', nRecords );
          Writeln(  'shapetype: ', nShapeType );
          case nShapeType of
            SHPT_NULL: Writeln(  'Shape is of type: NULL' );
            SHPT_POINT: Writeln(  'Shape is of type: POINT' );
            SHPT_ARC: Writeln(  'Shape is of type: ARC' );
            SHPT_POLYGON: Writeln(  'Shape is of type: POLYGON' );
            SHPT_MULTIPOINT: Writeln(  'Shape is of type: MULTIPOINT' );
            SHPT_POINTZ: Writeln(  'Shape is of type: POINTZ' );
            SHPT_ARCZ: Writeln(  'Shape is of type: ARCZ' );
            SHPT_POLYGONZ: Writeln(  'Shape is of type: POLYGONZ' );
            SHPT_MULTIPOINTZ: Writeln(  'Shape is of type: MULTIPOINTZ' );
            SHPT_POINTM: Writeln(  'Shape is of type: POINTM' );
            SHPT_ARCM: Writeln(  'Shape is of type: ARCM' );
            SHPT_POLYGONM: Writeln(  'Shape is of type: POLYGONM' );
            SHPT_MULTIPOINTM: Writeln(  'Shape is of type: MULTIPOINTM' );
            SHPT_MULTIPATCH: Writeln(  'Shape is of type: MULTIPATCH' );
          else
            Writeln(  'Shape is of unknown type.' );
          end;
          WriteToLogFile_No_CR( 'Boundsmin: ' );
          for i:=0 to 3 do begin
            WriteToLogFile_No_CRFmt( '%g ', [adBoundsMin[ i ]] );
          end;
          WriteToLogFile('');
          WriteToLogFile_No_CR( 'Boundsmax: ' );
          for i:=0 to 3 do begin
            WriteToLogFile_No_CRFmt( '%g ', [adBoundsMax[ i ]] );
          end;
          WriteToLogFile('');
          if ( nShapeType <> SHPT_POINT ) then
            Raise ENot_a_Point_Shape.CreateResFmt( @sNot_a_Point_Shape, [LabeledEditShapeName.Text] );

        {-Dump x, y values of shape}
//        for i:=0 to ShapeInfo.nRecords-1 do begin
//          psShape := SHPReadObject ( hSHPHandle, i );
//          with psShape^ do begin
//            Writeln(  padfX[0], padfY[ 0 ] );
//          end;
//          SHPDestroyObject( psShape );
//        end;

        S_Ansi := AnsiString( LabeledEditShapeName.Text );
        {-Open input dBase file, dump table structure information}
        hDBFHandle := DBFOpen(  PAnsiChar( S_Ansi ), PAnsiChar( 'rb' ) );

        {- Dump dBase table structure information of input file }
        FieldCount := DBFGetFieldCount( hDBFHandle );
        Writeln(  'FieldCount = ', FieldCount );
        New( PnWidth ); New( PnDecimals ); New( PDBFieldName );
        for i:=0 to FieldCount-1 do begin
          FieldType := DBFGetFieldInfo ( hDBFHandle, i, PAnsiCHAR( PDBFieldName ), PnWidth, PnDecimals );
          {-Dump field properties}
           WriteToLogFile_No_CRFmt( 'Field: %d', [i] );
          Case FieldType of
            FTString: WriteToLogFile_No_CR( ' [STRING], ' );
            FTInteger: WriteToLogFile_No_CR( ' [INTEGER], ' );
            FTDouble: WriteToLogFile_No_CR( ' [DOUBLE], ' );
            FTInvalid: WriteToLogFile_No_CR( ' [INVALID FIELDTYPE], ' );
          else
            WriteToLogFile_No_CR( ' [INVALID FIELDTYPE], ' );
          end;
          if ( PDBFieldName <> nil ) then begin
            WriteToLogFile_No_CRFmt( ' DBFieldName = [%s] ', [PDBFieldName^] );
            if FieldType = FTString then
              ListBoxWellCode.Items.Add( PDBFieldName^ );
            if FieldType = FTInteger then begin
              ListBoxCluster.Items.Add( PDBFieldName^ );
              ListBoxAquifer.Items.Add( PDBFieldName^ );
            end;
            if FieldType = FTDouble then
              ListBoxMeasured.Items.Add( PDBFieldName^ );
            if ( FieldType = FTInteger ) or  (FieldType = FTDouble ) then
              ListBoxWeight.Items.Add( PDBFieldName^ );
          end;
          if ( FieldType <> FTInvalid ) then begin
            if ( PnWidth <> nil ) then
              WriteToLogFile_No_CRFmt( ' Width = %d', [PnWidth^] );
            if ( PnDecimals <> nil ) then
              Writeln(  ' nDecimals = ', PnDecimals^ );
          end;
        end;

        {-Restore previously set item indices}
        with MainForm do begin
          for i:=0 to ComponentCount-1 do begin
            if Components[ i ] is TListBox  then begin
              with Components[ i ] as TListbox do begin
                with fini do begin
                  j := ReadInteger( cIni_Selection, Name, 0 );
                  if ( j >=0 ) and ( j <= Count ) then
                    ItemIndex := j
                  else
                    ItemIndex := 0;
                end;
              end;
            end;
          end;
        end;

        {-Dump dBase table }
        DBRecordCount := DBFGetRecordCount ( hDBFHandle );
        Writeln(  'DBRecordCount = ',  DBRecordCount );

{$ifdef test}

        New( PnWidth ); New( PnDecimals ); New( PDBFieldName );
        for i:= 0 to DBRecordCount-1 do begin
          Write( lf, 'Record ', i, ' ' );
          for j:=0 to FieldCount-1 do begin
            FieldType := DBFGetFieldInfo ( hDBFHandle, j, PAnsiCHAR( PDBFieldName ), PnWidth, PnDecimals );
            if ( PDBFieldName  <> nil ) then
              Write( lf, PDBFieldName^  + ' =' )
            else
              Write( lf, 'nilFieldName = ' );
            if ( PnWidth <> nil ) then begin
              Case FieldType of
                FTString: begin
                    aString := DBFReadStringAttribute (hDBFHandle, i, j );
                    Trim( aString );
                    if aString <> '' then begin
                      Write( lf, '"' + aString + '" ' );
                    end;
                  end;
                FTInteger: begin
                    aLongIntValue := DBFReadIntegerAttribute( hDBFHandle, i, j );
                    Write( lf, aLongIntValue, ' ' );
                  end;
                FTDouble: begin
                    aDoubleValue := DBFReadDoubleAttribute ( hDBFHandle, i, j );
                    Write( lf, aDoubleValue, ' ' );

                  end;
                else
                  Write( lf, 'InvalidFieldType' );
              end;
            end;
          end; {-for j}
          Writeln( lf );
        end; {-for i}

{$endif}

        SHPClose( hSHPHandle );
        DBFClose( hDBFHandle );

        end;
        CreateCHIButton.Visible := true;
        ReadShapeButton.Visible := false;

      Except
        On E: Exception do begin
          HandleError( E.Message, true );
          MessageBeep( MB_ICONASTERISK );
        end;
      End;
      Finally

      End;
    end;
  end;
end;

procedure TMainForm.LabeledEditShapeNameClick(Sender: TObject);
begin
 with OpenDialogShapeFile do begin
    if execute then begin
      LabeledEditShapeName.Text := ExpandFileName( FileName );
      fini.WriteString( cIni_Files, cIni_InputShapeFileName,
      LabeledEditShapeName.Text );
    end;
  end;
end;

end.
