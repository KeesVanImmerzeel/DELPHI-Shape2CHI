program Shape2CHI;

uses
  Forms,
  Sysutils,
  Dialogs,
  uError,
  uShape2CHI in 'uShape2CHI.pas' {MainForm},
  System.UITypes;

{$R *.RES}

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Try
    Try
      if ( Mode = Interactive ) then begin
        Application.Run;
      end else begin
        {MainForm.GoButton.Click;}
      end;
    Except
      Try WriteToLogFileFmt( 'Error in application: [%s].', [Application.ExeName] ); except end;
      MessageDlg( Format( 'Error in application: [%s].', [Application.ExeName] ), mtError, [mbOk], 0);
    end;
  Finally
  end;

end.
