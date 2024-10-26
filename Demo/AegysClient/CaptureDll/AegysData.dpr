library AegysData;

uses
  Sharemem,
  Variants,
  Windows,
  Winapi.Wincodec,
  Vcl.Forms,
  ActiveX,
  Vcl.Graphics,
  Winapi.Nb30,
  System.Classes,
  System.SysUtils,
  uAegysBase,
  UDesktopDuplication in 'UDesktopDuplication.pas';

Const
  cJPGQual         = 25;
  DeskWinSta       = 'winsta0\default';
  cCompressionData = True;

 Type
  TBitmapConversion    = Procedure (Var Result : TStream);

 Var
  BitsPerPixel        : Byte;
  WinSta              : HWINSTA;


{$R *.res}


Function GetDesktopHDESK(Name: String) : HDESK;
Begin
 Result := OpenDesktop(PChar(Name), 0, False,
                       DESKTOP_CREATEMENU    Or
                       DESKTOP_CREATEWINDOW  Or
                       DESKTOP_ENUMERATE     Or
                       DESKTOP_HOOKCONTROL   Or
                       DESKTOP_WRITEOBJECTS  Or
                       DESKTOP_READOBJECTS   Or
                       DESKTOP_SWITCHDESKTOP Or
                       GENERIC_WRITE);
End;

Function SwitchToDesktop(Desktop: HDESK): Boolean;overload;
Var
 OldDesktop: HDESK;
Begin
 Result := False;
 If Desktop = 0 Then
  Exit;
 OldDesktop := GetThreadDesktop(GetCurrentThreadId);
 If SetThreadDesktop(Desktop) Then
  Begin
   CloseDesktop(OldDesktop);
   Result := True;
  End;
End;

Function SwitchToDesktop(const Name: string): Boolean;overload;
Var
 Desktop: HDESK;
Begin
 Result := False;
 Desktop := GetDesktopHDESK(Name);
 If SwitchToDesktop(Desktop) then
  Result := True
 Else
  CloseDesktop(Desktop);
End;

Function EnumDesktopsProc(Name: PChar; lParam: LPARAM): Boolean;
Var
 WinStaName : string;
Begin
 WinStaName := String(lParam);
 SwitchToDesktop(Name);
 Result     := True;
End;

Function EnumWindowStationsProc(Name: PChar; lParam: LPARAM): Boolean;
Var
 S : String;
Begin
 S      := Name;
 WinSta := OpenWindowStation(Name, False, MAXIMUM_ALLOWED);
 EnumDesktopsProc(DeskWinSta, 0);
 Result := True;
End;

Function CaptureScreen(aMonitor : Real = 0) : TStream; StdCall; Export;
Var
 Bitmap    : TBitmap;
 hdcScreen : HDC;
 Procedure SaveBitmapAsJpeg(ImageQuality : Single;
                            Var Result   : TStream);
 Const
  PROPBAG2_TYPE_DATA = 1;
 Var
  ImagingFactory : IWICImagingFactory;
  Width,
  Height         : Integer;
  LoadStream     : IStream;
  Stream         : IWICStream;
  Encoder        : IWICBitmapEncoder;
  Frame          : IWICBitmapFrameEncode;
  PropBag        : IPropertyBag2;
  PropBagOptions : TPropBag2;
  V              : Variant;
  PixelFormat    : TGUID;
  Buffer         : TBytes;
  BitmapInfo     : TBitmapInfo;
  hBmp           : HBITMAP;
  WICBitmap      : IWICBitmap;
  Rect           : WICRect;
  aStreamAdapter : TStreamAdapter;
 Begin
  Try
   Width                           := Bitmap.Width;
   Height                          := Bitmap.Height;
   CoCreateInstance         (CLSID_WICImagingFactory, Nil,
                             CLSCTX_INPROC_SERVER     Or
                             CLSCTX_LOCAL_SERVER,
                             IUnknown, ImagingFactory);
   ImagingFactory.CreateStream(Stream);
   aStreamAdapter                  := TStreamAdapter.Create(Result);
   LoadStream                      := aStreamAdapter;
   Stream.InitializeFromIStream(LoadStream);
   ImagingFactory.CreateEncoder(GUID_ContainerFormatJpeg, GUID_NULL, Encoder);
   Encoder.Initialize(Stream, WICBitmapEncoderNoCache);
   CoUninitialize();
   Processmessages;
   Encoder.CreateNewFrame(Frame, PropBag);
   PropBagOptions                  := Default(TPropBag2);
   PropBagOptions.pstrName         := 'ImageQuality';
   PropBagOptions.dwType           := PROPBAG2_TYPE_DATA;
   PropBagOptions.vt               := VT_R4;
   V := VarAsType(0.01 * ImageQuality, varSingle);
   PropBag.Write(1, @PropBagOptions, @V);
   Frame.Initialize(PropBag);
   Frame.SetSize(Width, Height);
   If Bitmap.AlphaFormat = afDefined Then
    PixelFormat                    := GUID_WICPixelFormat32bppBGRA
   Else
    PixelFormat                    := GUID_WICPixelFormat32bppBGR;
   Bitmap.PixelFormat              := pf32bit;
   SetLength(Buffer, 4 * Width * Height);
   BitmapInfo                      := Default(TBitmapInfo);
   BitmapInfo.bmiHeader.biSize     := SizeOf(BitmapInfo);
   BitmapInfo.bmiHeader.biWidth    := Width;
   BitmapInfo.bmiHeader.biHeight   := -Height;
   BitmapInfo.bmiHeader.biPlanes   := 1;
   BitmapInfo.bmiHeader.biBitCount := 32;
   hBmp                            := Bitmap.Handle;
   GetDIBits(Bitmap.Canvas.Handle, hBmp, 0, Height, @Buffer[0], BitmapInfo, DIB_RGB_COLORS);
   ImagingFactory.CreateBitmapFromMemory(Width, Height, PixelFormat, 4 * Width,
                                         Length(Buffer), @Buffer[0], WICBitmap);
   Rect.X                          := 0;
   Rect.Y                          := 0;
   Rect.Width                      := Width;
   Rect.Height                     := Height;
   Frame.WriteSource(WICBitmap, @Rect);
   Frame.Commit;
   Encoder.Commit;
   Processmessages;
   SetLength(Buffer, 0);
  Finally
   Encoder        := Nil;
   ImagingFactory := Nil;
   ReleaseDC(0, hBmp);
  End;
 End;
Begin
 Try
  EnumWindowStationsProc(DeskWinSta, 0);
  hdcScreen          := GetDC(0);
  SetWindowDisplayAffinity(hdcScreen, WDA_MONITOR);
  Bitmap             := TBitmap.Create;
  Case BitsPerPixel Of
   8  : Bitmap.PixelFormat := pf8bit;
   16 : Bitmap.PixelFormat := pf16bit;
   24 : Bitmap.PixelFormat := pf24bit;
   32 : Bitmap.PixelFormat := pf32bit;
  End;
  Bitmap.SetSize(Screen.Width, Screen.Height);
  bitblt(Bitmap.Canvas.Handle, 0 ,0 , screen.Width, screen.Height, hdcScreen, 0, 0, SRCCOPY);
  CoInitializeEx(nil, COINIT_MULTITHREADED);
  Result       := TMemoryStream.Create;
  SaveBitmapAsJpeg(cJPGQual, Result);
 Finally
  ReleaseDC (0, hdcScreen);
  Bitmap.FreeImage;
  FreeAndNil(Bitmap);
  Processmessages;
  CloseWindowStation(WinSta);
 End;
End;

Exports
 CaptureScreen;

procedure DLLMain(dwReason: DWORD);
Begin
 Case dwReason of
  DLL_PROCESS_ATTACH : Begin

                       End; {= DLL_PROCESS_ATTACH =}
  DLL_PROCESS_DETACH : Begin
//                        If Assigned(DesktopDuplication) Then
//                         FreeAndNil(DesktopDuplication);
                       End;{= DLL_PROCESS_DETACH =}
 End; {= case =}
End; {= DLLMain =}

Begin
 DLLProc := @DLLMain;
 DLLMain(DLL_PROCESS_ATTACH);
end.

