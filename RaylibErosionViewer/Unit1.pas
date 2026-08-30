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
  FErosionViewer := TRaylibErosionViewer.Create(Self);
  FErosionViewer.Parent := Self;
  FErosionViewer.Align := alClient;
  FErosionViewer.Visible := True;
  FErosionViewer.Active := True;
end;

end.
