unit jpeg2pdf;

interface 

uses 
    Windows,Classes, Graphics, SysUtils; 

const ERR_SAVE=-1; 
      ERR_OK=-2; 
      ERR_ABORTED=-3; 

    // Convertit un fichier JPG en Fichier PDF 
    function JPGtoPDF(FileName, SaveName:String): integer; 

    // Convertit une liste de fichiers JPG en un seul fichier PDF 
    function ListeJPGToPDF(ListeJPG: TStrings ; SaveName:String): integer; 

    { Chaque fonction renvoit : 
      - ERR_OK si la création du fichier s'est bien déroulée 
      - ERR_SAVE s'il est impossible d'écrire dans le fichier de sortie
      - ERR_ABORTED en cas d'erreur imprévue durant la génération du PDF
      - pour JPGtoPDF : 0 si le fichier à insérer a posé problème 
      - pour ListeJPGtoPDF : toute valeur positive pour désigner l'indice du fichier ayant posé problème lors de son insertion 
    } 

implementation 

procedure Write_CrossReferenceTable(AStream: TStream; PosArray : array of Dword;Count:Integer); 
Var 
  i :Integer; 
begin 
  With TStringStream(AStream) do 
  begin 
    WriteString('xref'#10); 
    WriteString(Format('0 %d'#10,[Count+1])); 
    WriteString('0000000000 65535 f '#10); 
    for i:= 0 to Count-1 do 
    begin 
    WriteString(Format('%0.10d',[PosArray[i ]])+' 00000 n '#10); 
    end; 
  end; 
end; 

procedure Write_ContentsObject(AStream: TStream; Index : Dword; Width,Height : Integer); 
Var 
  MemoryStream : TMemoryStream; 
begin 
  MemoryStream:=TMemoryStream.Create; 
  Try 
    // Stream 
    With TStringStream(MemoryStream) do 
    begin 
      WriteString('q'#10); 
        WriteString(Format('%d 0 0 %d 0 0 cm'#10,[Width,Height])); 
        WriteString('/Im0 Do'#10); 
      WriteString('Q'#10); 
    end; 

    MemoryStream.Position:=0; 

    // Object 
    With TStringStream(AStream) do 
    begin 
      WriteString(Format('%d 0 obj'#10,[Index])); 
      WriteString(Format('<< /Length %d >>'#10,[MemoryStream.Size])); 
      WriteString('stream'#10); 
      AStream.CopyFrom(MemoryStream,MemoryStream.Size) ; 
      WriteString('endstream'#10); 
      WriteString('endobj'#10); 
    end; 
  finally 
    MemoryStream.Free; 
  end; 
end; 

function SwapEndian(S :word):word; 
begin 
Result :=(S and $00FF) shl 8 + (S and $FF00) shr 8  ; 
end; 

function GetJPEGSize(FileName:String;var AWidth,AHeight:Integer;var CMYK :Boolean):Boolean; 
var 
wrk      : Word ; 
Sampling : Byte; 
AStream  : TStream; 
const 
SOF0 : Word = $FFC0;  // Normal 
SOF2 : Word = $FFC2;  // Progressive 
begin 
  Result  := False;
  try
  AStream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite); 
  try 
      // JFIF 
      AStream.ReadBuffer(wrk,2); wrk:=SwapEndian(wrk); 
      if wrk<>$FFD8 then Exit; 

      While True do 
      begin 
        AStream.ReadBuffer(wrk,2); wrk:=SwapEndian(wrk); 

        // JPEG Maker 
        if (wrk= SOF0) or (wrk= SOF2)  then 
        begin 
            // Skip Segment Length 
            AStream.Position:= AStream.Position+2; 
            // Skip Sample 
            AStream.Position:= AStream.Position+1; 
            // Height 
            AStream.ReadBuffer(wrk,2); AHeight :=SwapEndian(wrk); 
            // Width 
            AStream.ReadBuffer(wrk,2); AWidth  :=SwapEndian(wrk); 

            // ColorMode 
            AStream.ReadBuffer(Sampling,1); 
            case Sampling of 
                3  : CMYK :=False;  // RGB 
                4  : CMYK :=True    // CMYK 
              else Break;          // ??? 
            end; 

            Result :=True; 
            Break; 
        end 
        else if (wrk=$FFFF) or (wrk=$FFD9) then 
        begin 
            Break; 
        end; 

        // Skip Segment @ 
        AStream.ReadBuffer(wrk,2); wrk:=SwapEndian(wrk); 
        AStream.Position:= AStream.Position+(wrk-2); 
      end; 

  finally
    AStream.Free;
  end;
  except end; 
end; 


function JPGtoPDF(FileName, SaveName:String): integer; 
var Liste: TStringList; 
begin 
    Liste:=TStringList.Create; 
    Liste.Add(FileName);
    result:=ListeJPGToPDF(Liste, SaveName);
    Liste.Free;
end;

function ListeJPGToPDF(ListeJPG: TStrings ; SaveName: string): integer; 
type TInfosJPG=record 
    CMYK: boolean; 
    W, H: integer; 
end; 
var 
  InfosJPG: array of TInfosJPG; 
  AStream,JPGStream : TStream; 
  ObjectIndex, W, H  : Integer; 
  CMYK: boolean; 
  ObjectPosArray  : array of Dword;
  i: integer;
  Bon: bool;
begin
     if SaveName='' then
     begin
          result:=ERR_SAVE;
          exit;
     end
     else
     begin
          Bon:=true; i:=0;
          while (i<ListeJPG.Count) and Bon do
          begin
              if (ListeJPG[i ]='') or not FileExists(ListeJPG[i ]) or not GetJPEGSize(ListeJPG[i ],W,H,CMYK) then Bon:=false else
              begin
                    Setlength(InfosJPG, length(InfosJPG)+1);
                    InfosJPG[length(InfosJPG)-1].CMYK:=CMYK;
                    InfosJPG[length(InfosJPG)-1].W:=W;
                    InfosJPG[length(InfosJPG)-1].H:=H;
                    Inc(i);
              end;
          end;
          if not Bon then
          begin
              result:=i;
              Setlength(InfosJPG, 0);
              exit;
          end;
     end;

     ObjectIndex :=0;

     try
        AStream:=TFileStream.Create(SaveName,fmCreate);
     except
        result:=ERR_SAVE;
        exit;
     end;

     Setlength(ObjectPosArray, 3*length(InfosJPG)+3);
     try
       // PDF version
       TStringStream(AStream).WriteString('%PDF-1.2'#10);

       // Catalog
       ObjectPosArray[ObjectIndex] :=AStream.Position;
       With TStringStream(AStream) do
       begin
            WriteString(Format('%d 0 obj'#10,[ObjectIndex+1]));
            WriteString('<<'#10);
            WriteString('/Type /Catalog'#10);
            WriteString('/Pages 2 0 R'#10);
            WriteString('/OpenAction [3 0 R /XYZ -32768 -32768 1 ]'#10); // View Option (100%)
            WriteString('>>'#10);
            WriteString('endobj'#10);
       end;
       Inc(ObjectIndex);

       // Parent Pages
       ObjectPosArray[ObjectIndex] :=AStream.Position;
       With TStringStream(AStream) do
       begin
            WriteString(Format('%d 0 obj'#10,[ObjectIndex+1]));
            WriteString('<<'#10);
            WriteString('/Type /Pages'#10);
            WriteString('/Kids [ ');
            for i:=0 to length(InfosJPG)-1 do WriteString(inttostr(ObjectIndex+2+i)+' 0 R ');
            WriteString(']'#10);
            WriteString('/Count '+inttostr(length(InfosJPG))+#10);
            WriteString('>>'#10);
            WriteString('endobj'#10);
       end;
       Inc(ObjectIndex);

       // Kids Page
       for i:=0 to length(InfosJPG)-1 do
       begin
            ObjectPosArray[ObjectIndex] :=AStream.Position;
            With TStringStream(AStream) do
            begin
                WriteString(Format('%d 0 obj'#10,[ObjectIndex+1]));
                WriteString('<<'#10);
                WriteString('/Type /Page'#10);
                WriteString('/Parent 2 0 R'#10);
                WriteString('/Resources'#10);
                WriteString('<<'#10);
                WriteString('/XObject << /Im0 '+inttostr(i+length(InfosJPG)+3)+' 0 R >>'#10);
                WriteString('/ProcSet [ /PDF /ImageC ]'#10);
                WriteString('>>'#10);
                WriteString(Format('/MediaBox [ 0 0 %d %d ]'#10, [InfosJPG[i ].W,InfosJPG[i ].H]));
                WriteString('/Contents '+inttostr(i+2*length(InfosJPG)+3)+' 0 R'#10);
                WriteString('>>'#10);
                WriteString('endobj'#10);
            end;
            Inc(ObjectIndex);
       end;

       // XObject Resource
       for i:=0 to length(InfosJPG)-1 do
       begin
            ObjectPosArray[ObjectIndex] :=AStream.Position;
            With TStringStream(AStream) do
            begin
                WriteString(Format('%d 0 obj'#10,[ObjectIndex+1]));
                WriteString('<<'#10);
                WriteString('/Type /XObject'#10);
                WriteString('/Subtype /Image'#10);
                WriteString('/Name /Im0'#10);
                WriteString(Format('/Width %d'#10,[InfosJPG[i ].W]));
                WriteString(Format('/Height %d'#10,[InfosJPG[i ].H]));
                WriteString('/BitsPerComponent 8'#10);
                WriteString('/Filter [/DCTDecode]'#10);
                if not InfosJPG[i ].CMYK then
                  WriteString('/ColorSpace /DeviceRGB'#10)
                else
                begin
                      WriteString('/ColorSpace /DeviceCMYK'#10);
                      WriteString('/Decode[1 0 1 0 1 0 1 0]'#10); // Photoshop CMYK (NOT BIT)
                end;
                JPGStream :=TFileStream.Create(ListeJPG[i ], fmOpenRead or fmShareDenyWrite);
                WriteString(Format('/Length %d >>'#10,[JPGStream.Size]));
                WriteString('stream'#10);
                AStream.CopyFrom(JPGStream,JPGStream.Size);
                JPGStream.Free;
                WriteString('endstream'#10);
                WriteString('endobj'#10);
            end;
            Inc(ObjectIndex);
       end;

       // Contents Stream & Object
       for i:=0 to length(InfosJPG)-1 do
       begin
            ObjectPosArray[ObjectIndex] :=AStream.Position;
            Write_ContentsObject(AStream,ObjectIndex+1,InfosJPG[i ].W,InfosJPG[i ].H);
            Inc(ObjectIndex);
       end;

       // CrossReferenceTable
       ObjectPosArray[ObjectIndex] :=AStream.Position;
       Write_CrossReferenceTable(AStream,ObjectPosArray,ObjectIndex);

       // Trailer
       With TStringStream(AStream) do
       begin
            WriteString('trailer'#10);
            WriteString('<<'#10);
            WriteString(Format('/Size %d'#10,[ObjectIndex+1]));
            WriteString('/Root 1 0 R'#10);
            WriteString('>>'#10);
            WriteString('startxref'#10);
            WriteString(Format('%d'#10,[ObjectPosArray[ObjectIndex]]));
            WriteString('%%EOF');
       end;
       AStream.Free;
       result:=ERR_OK;
     except
       result:=ERR_ABORTED;
       AStream.Free;
     end;
     Setlength(ObjectPosArray, 0);
end;

end.
