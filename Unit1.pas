unit Unit1;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, ExtCtrls, ExtDlgs, jpeg;

type
  TForm1 = class(TForm)
    Button1: TButton;
    Button2: TButton;
    OpenPictureDialog1: TOpenPictureDialog;
    Button3: TButton;
    SaveDialog1: TSaveDialog;
    Label1: TLabel;
    ListBox1: TListBox;
    procedure Button1Click(Sender: TObject);
    procedure Button3Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
  private
    { Déclarations privées }
  public
    { Déclarations publiques }
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

uses jpeg2pdf;

procedure TForm1.Button1Click(Sender: TObject);
var i: integer;
begin
     if OpenPictureDialog1.Execute then for i:=0 to OpenPictureDialog1.Files.Count-1 do ListBox1.Items.Add(OpenPictureDialog1.Files[i]);
     Button2.Enabled:=ListBox1.Count<>0;
     Button3.Enabled:=ListBox1.Count<>0;
end;

procedure TForm1.Button2Click(Sender: TObject);
begin
     if ListBox1.SelCount<>0 then ListBox1.DeleteSelected;
     Button2.Enabled:=ListBox1.Count<>0;
     Button3.Enabled:=ListBox1.Count<>0;
end;

procedure TForm1.Button3Click(Sender: TObject);
var k: integer;
begin
     if SaveDialog1.Execute then
     begin
          k:=ListeJPGtoPDF(ListBox1.Items, SaveDialog1.FileName);
          case k of
          ERR_OK: MessageDlg(#13'Création terminée !',mtInformation,[mbOk],0);
          ERR_SAVE: MessageDlg(#13'Impossible d''écrire dans le fichier de sortie !',mtError,[mbOk],0);
          ERR_ABORTED: MessageDlg(#13'Erreur inattendue !',mtError,[mbOk],0);
          else
          MessageDlg(#13'Problème lors de l''insertion de l''image n°'+inttostr(k)+'.',mtError,[mbOk],0);
          end;
     end;
end;

end.
