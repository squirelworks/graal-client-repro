{ Secure6113: the 6.1.1.3 parameters for the Seihai SEI00001 secure login.

  The handshake itself is the shared code in common/GSecLogin (TSecHandshake
  and TSecSession) over common/GSecCrypto. This unit only holds what is
  specific to the 6.1.1.3 build: the inner token it announces and the login
  tail it seals.

  SEI00001 is Seihai's own login (seihai/documentation/secure-login.md); it
  is not part of any Graal build and no real 6.1.1.3 client sends it. A
  rebuild that talks to a Seihai server can use it so the account and
  password are not sent in the clear.

  The 6.1.1.3 type and key bytes of the C1 prefix were not recovered
  (Frame6113's Id50Gap), so the caller supplies the prefix; the key byte
  only seeds the post-login cipher, which this login does not reach. }
unit Secure6113;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
  { The 6.1.1.3 build token (GNP1905C), used as the SEI00001 inner token for
    a Seihai login. A real client receives this token from its connector in
    conf.gs; here it is the build's own identifier on the inner allow-list. }
  Sei6113Inner = 'GNP1905C';

{ The classic login tail SEI00001 seals in C2: GSTRING account, GSTRING
  password, then any platform fields (empty when not supplied). }
function Sei6113Tail(const Account, Password, Platform: string): string;

implementation

uses
  GTypes;

function Sei6113Tail(const Account, Password, Platform: string): string;
begin
  Result := GString(Account) + GString(Password) + Platform;
end;

end.
