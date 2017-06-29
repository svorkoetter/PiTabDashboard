unit Main; // vim:sw=2:

{$mode delphi}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls;

{ TMainForm }

type
  TMainForm = class(TForm)
    PowerSavingCheckBox: TCheckBox;
    OptionPanel: TPanel;
    EnergyCaption: TLabel;
    CoreCaption: TLabel;
    CoreLabel: TLabel;
    CoreMeter: TImage;
    USBCheckBox: TCheckBox;
    WirelessCheckbox: TCheckBox;
    VoltageMeter: TImage;
    EnergyMeter: TImage;
    VoltageLabel: TLabel;
    EnergyLabel: TLabel;
    VoltageCaption: TLabel;
    RefreshTimer: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormActivate(Sender: TObject);
    procedure FormClick(Sender: TObject);
    procedure FormWindowStateChange(Sender: TObject);
    procedure SettingsChanged(Sender: TObject);
    procedure RefreshTimerTimer(Sender: TObject);
  private
    { private declarations }
    lastV: Real;
    lastE, lastC1, lastC2, lastT, cycle: Integer;
    firstActivate: Boolean;
  public
    { public declarations }
  end;

var
  MainForm: TMainForm;

implementation

uses
  Math;

{$R *.lfm}

const
  CMD_FILE: string = '/ram/pitabd.cmd';
  DAT_FILE: string = '/ram/pitabd.dat';

  TEMP_SENSOR: string = '/sys/class/thermal/thermal_zone0/temp';
  // LOAD_AVERAGE: string = '/proc/loadavg';

{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  firstActivate := true;
  lastV := 0.0;
  lasTE := 0;
  lastC1 := 0;
  lastC2 := 0;
  lastT := 0;
  cycle := 0
end;

procedure TMainForm.FormActivate(Sender: TObject);
var
  fp: TextFile;
  box1, box2, box3: Integer;
begin
  (* Restore saved settings the first time the form is shown. *)
  if firstActivate then begin
    AssignFile(fp,CMD_FILE);
    {$I-}
    Reset(fp);
    {$I+}
    if IOResult = 0 then begin
      ReadLn(fp,box1,box2,box3);
      CloseFile(fp);
      PowerSavingCheckBox.Checked := (box1 = 1);
      USBCheckBox.Checked := (box2 = 1);
      WirelessCheckBox.Checked := (box3 = 1)
    end;
    firstActivate := false
  end
end;

procedure TMainForm.FormClick(Sender: TObject);
begin
  (* Clicking anywhere outside of the checkbox area minimizes the dashboard. *)
  Application.Minimize;
end;

procedure TMainForm.FormWindowStateChange(Sender: TObject);
begin
  (* Update the application title (and thus taskbar icon) when the dashboard
     is minimized or restored. *)
  RefreshTimerTimer(Sender)
end;

procedure TMainForm.SettingsChanged(Sender: TObject);
var
  fp: TextFile;
  box1, box2, box3: Integer;
begin
  (* Record the changed settings to inform the daemon. *)
  AssignFile(fp,CMD_FILE);
  {$I-}
  Rewrite(fp);
  {$I+}
  if IOResult = 0 then begin
    if PowerSavingCheckBox.Checked then box1 := 1 else box1 := 0;
    if USBCheckBox.Checked then box2 := 1 else box2 := 0;
    if WirelessCheckBox.Checked then box3 := 1 else box3 := 0;
    WriteLn(fp,box1,' ',box2,' ',box3);
    CloseFile(fp)
  end
end;

procedure TMainForm.RefreshTimerTimer(Sender: TObject);
var
  fp: TextFile;
  v, t: Real;
  e, c1, c2, ti: Integer;
  bmp: TBitMap;
  iconBG: TColor;
  readOK: Boolean;

  procedure DrawGauge( canvas: TCanvas; val, min, mid1, mid2, max: Real;
		       cFG, cBG, cMin, cMid1, cMid2, cMax: TColor );
  var
    rect: TRect;
    h: Integer;

    function GammaInterpolate( a, b: Integer; w: Real ): Integer;
    begin
      GammaInterpolate :=
	Round(Power(Power(a/255,2.2)*(1-w) + Power(b/255,2.2)*w, 1/2.2) * 255)
    end;

    function InterpolateColor( val, min, max: Real; cMin, cMax: TColor ): TColor;
    var
      rMin, gMin, bMin, rMax, gMax, bMax: Integer;
      w: Real;
    begin
      if val <= min then
        InterpolateColor := cMin
      else if val >= max then
        InterpolateColor := cMax
      else begin
	rMin := cMin and $FF;
	gMin := (cMin shr 8) and $FF;
	bMin := (cMin shr 16) and $FF;
	rMax := cMax and $FF;
	gMax := (cMax shr 8) and $FF;
	bMax := (cMax shr 16) and $FF;
	w := (val - min) / (max - min);
	InterpolateColor := TColor(
	  GammaInterpolate(rMin,rMax,w)
	  or (GammaInterpolate(gMin,gMax,w) shl 8)
	  or (GammaInterpolate(bMin,bMax,w) shl 16))
      end
    end;

  begin
    (* Force the canvas to be allocated. *)
    canvas.Pixels[0,0] := clRed;

    (* Draw the outline and background. *)
    rect.Top := 0;
    rect.Left := 0;
    rect.Bottom := canvas.Height;
    rect.Right := canvas.Width;

    canvas.Pen.Color := cFG;
    canvas.Brush.Color := cBG;
    canvas.Rectangle(rect);

    (* Only draw an indication on the meter if val is at least the minimum. *)
    if val < min then EXIT;

    (* Cap the indication at the maximum. *)
    if val > max then val := max;

    (* Determine the sub-part of the rectangle to fill with color. To aid
       readability, the minimum reading is one pixel, not zero. *)
    h := Round((val - min) / (max - min) * (rect.Bottom - rect.Top - 3));
    rect.Top := rect.Bottom - 2 - h;
    rect.Left := rect.Left + 1;
    rect.Bottom := rect.Bottom - 1;
    rect.Right := rect.Right - 1;

    (* Determine color depending on the range val falls in. *)
    if val < mid1 then
      canvas.Pen.Color := InterpolateColor(val,min,mid1,cMin,cMid1)
    else if val < mid2 then
      canvas.Pen.Color := InterpolateColor(val,mid1,mid2,cMid1,cMid2)
    else
      canvas.Pen.Color := InterpolateColor(val,mid2,max,cMid2,cMax);
    canvas.Brush.Color := canvas.Pen.Color;
    canvas.Rectangle(rect)
  end;

  procedure DrawLightningBolt( canvas: TCanvas );
  var
    bolt: array [1..6] of TPoint;
    x0, y0, i, s: Integer;
  begin
    (* Find the centre of the canvas, which also gives the half-width and
       half-height of the canvas. *)
    x0 := canvas.Width div 2;
    y0 := canvas.Height div 2;

    (* Points comprising the top half of the lightning bolt. Scaling is based
       on the height, and assumes the canvas is not wider than it is high. *)
    s := y0; if s > 40 then s := 40;
    bolt[1].x := x0 + (2 * s) div 5;
    bolt[1].y := y0 - (4 * s) div 5;
    bolt[2].x := x0 + s div 10;
    bolt[2].y := y0 - s div 10;
    bolt[3].x := bolt[1].x; // x0 + (3 * y0) div 10;
    bolt[3].y := bolt[2].y;

    (* The bottom half is the same as the top, rotated 180 degrees. *)
    for i := 1 to 3 do begin
      bolt[i+3].x := x0 - (bolt[i].x - x0);
      bolt[i+3].y := y0 + (y0 - bolt[i].y)
    end;

    (* Draw bolt, solid white. *)
    canvas.Pen.Color := clWhite;
    canvas.Brush.Color := clWhite;
    canvas.Polygon(bolt,false)
  end;

const
  RED = $0000FF;
  AMBER = $00DDFF;
  GREEN = $00EE00;

begin
  (* Read the data produced by pitabd. *)
  readOK := false;
  AssignFile(fp,DAT_FILE);
  {$I-}
  Reset(fp);
  {$I+}
  if IOResult = 0 then begin
    {$I-}
    ReadLn(fp,v,e,c1,c2);
    {$I+}
    readOK := (IOResult = 0);
    CloseFile(fp)
  end;

  (* Update the gauges if the data was read successfully. *)
  if readOK and (0.0 < v) and (v < 5.0) and (0.0 <= e) and (e <= 100.0)
  and ((c1 = 0) or (c1 = 1)) and ((c2 = 0) or (c2 = 1)) then begin

    (* Update voltage gauge. *)
    if v <> lastV then begin
      VoltageCaption.Caption := Format('%4.2fV',[v]);
      DrawGauge(VoltageMeter.canvas,v,3.2,3.72,3.81,4.2,
		clTeal,clSilver,RED,AMBER,GREEN,GREEN)
    end;

    (* Update energy gauge. *)
    if (e <> lastE) or (c1 <> lastC1) or (c2 <> lastC2) then begin
      EnergyCaption.Caption := Format('%d%%',[e]);
      DrawGauge(EnergyMeter.canvas,e,0,20,50,100,
		clTeal,clSilver,RED,AMBER,GREEN,GREEN);
      if (c1 = 1) or (c2 = 1) then
        DrawLightningBolt(EnergyMeter.canvas)
    end;

    (* Update window and taskbar caption to display energy. *)
    if (e <> lastE) or (Sender <> RefreshTimer) then begin
      if WindowState = wsMinimized then
	Caption := EnergyCaption.Caption
      else
	Caption := '[' + EnergyCaption.Caption + ']'
    end;

    (* Update window and taskbar icon to display energy. *)
    if (e <> lastE) or (e <= 5) or (c1 <> lastC1) or (c2 <> lastC2)
    or (c1 = 1) then begin
      bmp := TBitMap.Create;
      bmp.Width := 32;
      bmp.Height := 32;
      iconBG := clSilver;
      if (e <= 5) and Odd(cycle) and (c1 = 0) then iconBG := clRed;
      DrawGauge(bmp.canvas,e,0,20,50,100,
		clTeal,iconBG,RED,AMBER,GREEN,GREEN);
      if (c1 = 1) and Odd(cycle) or (c2 = 1) then
        DrawLightningBolt(bmp.canvas);
      Icon.Assign(bmp);
      bmp.Free
    end;

    (* Change refresh interval to allow blinking under certain conditions. *)
    if c1 = 1 then
      (* Blink lightning bolt while charging once per second. *)
      RefreshTimer.Interval := 500
    else if e <= 5 then
      (* Blink low energy level twice per second. *)
      RefreshTimer.Interval := 250
    else
      (* Otherwise refresh every five seconds. *)
      RefreshTimer.Interval := 5000;

    (* Record current state so we can detect changes. *)
    lastV := v; lastE := e; lastC1 := c1; lastC2 := c2
  end;

  (* Read the CPU/GPU temperature sensor. *)
  readOK := false;
  AssignFile(fp,TEMP_SENSOR);
  {$I-}
  Reset(fp);
  {$I+}
  if IOResult = 0 then begin
    {$I-}
    ReadLn(fp,ti);
    {$I+}
    readOK := (IOResult = 0);
    CloseFile(fp)
  end;

  (* Update the temperature gauge if the sensor was read successfully. *)
  if readOK and (0 < ti) and (ti < 100000) and (ti <> lastT) then begin
    t := Round(ti * 0.001);
    CoreCaption.Caption := Format('%2.0f'+#$C2+#$B0+'C',[t]);
    DrawGauge(CoreMeter.canvas,t,20,40,70,90,
	      clTeal,clSilver,$FF2211,$FF1177,$7700FF,$0000FF);
    lastT := ti
  end;

  INC(cycle)
end;

end.
