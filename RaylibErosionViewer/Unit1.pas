unit Unit1;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, RaylibErosionViewer;

type
  TForm1 = class(TForm)
    procedure FormCreate(Sender: TObject);
  private
    { Private-Deklarationen }
    FErosionViewer: TRaylibErosionViewer;
  public
    { Public-Deklarationen }

  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

procedure TForm1.FormCreate(Sender: TObject);
begin
  // Erstelle die Komponente und binde sie an die Form
  FErosionViewer := TRaylibErosionViewer.Create(Self);
  FErosionViewer.Parent := Self;
  FErosionViewer.Align := alClient;
  FErosionViewer.Visible := True;

  // Starte die Engine und den Background-Thread
  FErosionViewer.Active := True;
end;

end.
