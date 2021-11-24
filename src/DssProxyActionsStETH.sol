// SPDX-License-Identifier: AGPL-3.0-or-later

/// DssProxyActionsStETH.sol

// Copyright (C) 2021 Dai Foundation

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.6.12;

interface GemLike {
    function approve(address, uint256) external;
    function transfer(address, uint256) external;
    function transferFrom(address, address, uint256) external;
    function wrap(uint256 ) external returns (uint256);
    function unwrap(uint256) external returns (uint256);
    function stETH() external view returns (address);
    function getWstETHByStETH(uint256) external view returns (uint256);
}

interface ManagerLike {
    function ilks(uint256) external view returns (bytes32);
    function owns(uint256) external view returns (address);
    function urns(uint256) external view returns (address);
    function vat() external view returns (address);
    function open(bytes32, address) external returns (uint256);
    function give(uint256, address) external;
    function frob(uint256, int256, int256) external;
    function flux(uint256, address, uint256) external;
    function move(uint256, address, uint256) external;
    function exit(address, uint256, address, uint256) external;
    function quit(uint256, address) external;
}

interface VatLike {
    function can(address, address) external view returns (uint256);
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
    function dai(address) external view returns (uint256);
    function urns(bytes32, address) external view returns (uint256, uint256);
    function frob(bytes32, address, address, address, int256, int256) external;
    function hope(address) external;
}

interface GemJoinLike {
    function dec() external returns (uint256);
    function gem() external returns (GemLike);
    function join(address, uint256) external payable;
    function exit(address, uint256) external;
}

interface DaiJoinLike {
    function vat() external returns (VatLike);
    function dai() external returns (GemLike);
    function join(address, uint256) external payable;
    function exit(address, uint256) external;
}

interface EndLike {
    function fix(bytes32) external view returns (uint256);
    function cash(bytes32, uint256) external;
    function free(bytes32) external;
    function skim(bytes32, address) external;
}

interface JugLike {
    function drip(bytes32) external returns (uint256);
}

// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// WARNING: These functions meant to be used as a a library for a DSProxy. Some are unsafe if you call them directly.
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

contract Common {
    uint256 constant RAY = 10 ** 27;

    VatLike     immutable public vat;
    ManagerLike immutable public manager;

    constructor(address vat_, address manager_) public {
        vat = VatLike(vat_);
        manager = ManagerLike(manager_);
    }

    // Internal functions

    function _mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "mul-overflow");
    }

    // Public functions

    function daiJoin_join(address daiJoin, address urn, uint256 wad) public {
        GemLike dai = DaiJoinLike(daiJoin).dai();
        // Gets DAI from the user's wallet
        dai.transferFrom(msg.sender, address(this), wad);
        // Approves adapter to take the DAI amount
        dai.approve(daiJoin, wad);
        // Joins DAI into the vat
        DaiJoinLike(daiJoin).join(urn, wad);
    }
}

contract DssProxyActionsStETH is Common {

    constructor(address vat_, address manager_) public Common(vat_, manager_) {}

    // Internal functions

    function _toInt256(uint256 x) internal pure returns (int256 y) {
        y = int256(x);
        require(y >= 0, "int-overflow");
    }

    function _toRad(uint256 wad) internal pure returns (uint256 rad) {
        rad = _mul(wad, 10 ** 27);
    }

    function _getDrawDart(
        address jug,
        address urn,
        bytes32 ilk,
        uint256 wad
    ) internal returns (int256 dart) {
        // Updates stability fee rate
        uint256 rate = JugLike(jug).drip(ilk);

        // Gets DAI balance of the urn in the vat
        uint256 dai = vat.dai(urn);

        // If there was already enough DAI in the vat balance, just exits it without adding more debt
        uint256 rad = _mul(wad, RAY);
        if (dai < rad) {
            uint256 toDraw = rad - dai; // dai < rad
            // Calculates the needed dart so together with the existing dai in the vat is enough to exit wad amount of DAI tokens
            dart = _toInt256(toDraw / rate);
            // This is neeeded due lack of precision. It might need to sum an extra dart wei (for the given DAI wad amount)
            dart = _mul(uint256(dart), rate) < toDraw ? dart + 1 : dart;
        }
    }

    function _getWipeDart(
        uint256 dai,
        address urn,
        bytes32 ilk
    ) internal view returns (int256 dart) {
        // Gets actual rate from the vat
        (, uint256 rate,,,) = vat.ilks(ilk);
        // Gets actual art value of the urn
        (, uint256 art) = vat.urns(ilk, urn);

        // Uses the whole dai balance in the vat to reduce the debt
        dart = _toInt256(dai / rate);
        // Checks the calculated dart is not higher than urn.art (total debt), otherwise uses its value
        dart = uint256(dart) <= art ? - dart : - _toInt256(art);
    }

    function _getWipeAllWad(
        address usr,
        address urn,
        bytes32 ilk
    ) internal view returns (uint256 wad) {
        // Gets actual rate from the vat
        (, uint256 rate,,,) = vat.ilks(ilk);
        // Gets actual art value of the urn
        (, uint256 art) = vat.urns(ilk, urn);

        // Gets DAI balance of the urn in the vat
        uint256 dai = vat.dai(usr);

        // If there was already enough DAI in the vat balance, no need to join more
        uint256 debt = _mul(art, rate);
        if (debt > dai) {
            uint256 rad = debt - dai;
            wad = rad / RAY;

            // If the rad precision has some dust, it will need to request for 1 extra wad wei
            wad = _mul(wad, RAY) < rad ? wad + 1 : wad;
        }
    }

    function _open(
        bytes32 ilk,
        address usr
    ) internal returns (uint256 cdp) {
        cdp = manager.open(ilk, usr);
    }

    function _flux(
        uint256 cdp,
        address dst,
        uint256 wad
    ) internal {
        manager.flux(cdp, dst, wad);
    }

    function _move(
        uint256 cdp,
        address dst,
        uint256 rad
    ) internal {
        manager.move(cdp, dst, rad);
    }

    function _frob(
        uint256 cdp,
        int256 dink,
        int256 dart
    ) internal {
        manager.frob(cdp, dink, dart);
    }

    // Public functions

    function stETHJoin_join(address WstETHJoin, address urn, uint256 amt) public returns (uint256 wad) {
        GemLike gem = GemJoinLike(WstETHJoin).gem();
        GemLike stETH = GemLike(gem.stETH());
        // Gets token from the user's wallet
        stETH.transferFrom(msg.sender, address(this), amt);
        // Approves wrapping
        stETH.approve(address(gem), amt);
        // Wraps StETH in WstETH
        wad = gem.wrap(amt);
        // Approves adapter to take the WstETH amount
        gem.approve(address(WstETHJoin), wad);
        // Joins WstETH collateral into the vat
        GemJoinLike(WstETHJoin).join(urn, wad);
    }

    function lockStETH(
        address WstETHJoin,
        uint256 cdp,
        uint256 amt
    ) public {
        // Receives stETH amount, converts it to WstETH and joins it into the vat
        uint256 wad = stETHJoin_join(WstETHJoin, address(this), amt);
        // Locks WstETH amount into the CDP
        vat.frob(
            manager.ilks(cdp),
            manager.urns(cdp),
            address(this),
            address(this),
            _toInt256(wad),
            0
        );
    }

    function safeLockStETH(
        address WstETHJoin,
        uint256 cdp,
        uint256 amt,
        address owner
    ) public {
        require(manager.owns(cdp) == owner, "owner-missmatch");
        lockStETH(WstETHJoin, cdp, amt);
    }

    function freeStETH(
        address WstETHJoin,
        uint256 cdp,
        uint256 amt
    ) public {
        GemLike gem = GemJoinLike(WstETHJoin).gem();
        // Calculates how much WstETH to free
        uint256 wad = gem.getWstETHByStETH(amt);
        // Unlocks WstETH amount from the CDP
        _frob(cdp, -_toInt256(wad), 0);
        // Moves the amount from the CDP urn to proxy's address
        _flux(cdp, address(this), wad);
        // Exits WstETH amount to proxy address as a token
        GemJoinLike(WstETHJoin).exit(address(this), wad);
        // Converts WstETH to StETH
        uint256 unwrapped = gem.unwrap(wad);
        // Sends StETH back to the user's wallet
        GemLike(gem.stETH()).transfer(msg.sender, unwrapped);
    }

    function exitStETH(
        address WstETHJoin,
        uint256 cdp,
        uint256 amt
    ) public {
        GemLike gem = GemJoinLike(WstETHJoin).gem();
        // Calculates how much WstETH to exit
        uint256 wad = gem.getWstETHByStETH(amt);
        // Moves the amount from the CDP urn to proxy's address
        _flux(cdp, address(this), wad);
        // Exits WstETH amount to proxy address as a token
        GemJoinLike(WstETHJoin).exit(address(this), wad);
        // Converts WstETH to StETH
        uint256 unwrapped = gem.unwrap(wad);
        // Sends StETH back to the user's wallet
        GemLike(gem.stETH()).transfer(msg.sender, unwrapped);
    }

    function lockStETHAndDraw(
        address jug,
        address WstETHJoin,
        address daiJoin,
        uint256 cdp,
        uint256 amtC,
        uint256 wadD
    ) public {
        address urn = manager.urns(cdp);
        // Receives stETH amount, converts it to WstETH and joins it into the vat
        uint256 wad = stETHJoin_join(WstETHJoin, urn, amtC);
        // Locks WstETH amount into the CDP and generates debt
        _frob(
            cdp,
            _toInt256(wad),
            _getDrawDart(
                jug,
                urn,
                manager.ilks(cdp),
                wadD
            )
        );
        // Moves the DAI amount (balance in the vat in rad) to proxy's address
        _move(cdp, address(this), _toRad(wadD));
        // Allows adapter to access to proxy's DAI balance in the vat
        if (vat.can(address(this), address(daiJoin)) == 0) {
            vat.hope(daiJoin);
        }
        // Exits DAI to the user's wallet as a token
        DaiJoinLike(daiJoin).exit(msg.sender, wadD);
    }

    function openLockStETHAndDraw(
        address jug,
        address WstETHJoin,
        address daiJoin,
        bytes32 ilk,
        uint256 amtC,
        uint256 wadD
    ) public returns (uint256 cdp) {
        cdp = _open(ilk, address(this));
        lockStETHAndDraw(jug, WstETHJoin, daiJoin, cdp, amtC, wadD);
    }

    function wipeAndFreeStETH(
        address WstETHJoin,
        address daiJoin,
        uint256 cdp,
        uint256 amtC,
        uint256 wadD
    ) public {
        address urn = manager.urns(cdp);
        GemLike gem = GemJoinLike(WstETHJoin).gem();

        // Joins DAI amount into the vat
        daiJoin_join(daiJoin, urn, wadD);
        // Calculates how much WstETH to exit
        uint256 wadC = gem.getWstETHByStETH(amtC);
        // Paybacks debt to the CDP and unlocks WstETH amount from it
        _frob(
            cdp,
            -_toInt256(wadC),
            _getWipeDart(
                vat.dai(urn),
                urn,
                manager.ilks(cdp)
            )
        );
        // Moves the amount from the CDP urn to proxy's address
        _flux(cdp, address(this), wadC);
        // Exits WstETH amount to proxy address as a token
        GemJoinLike(WstETHJoin).exit(address(this), wadC);
        // Converts WstETH to StETH
        uint256 unwrapped = gem.unwrap(wadC);
        // Sends StETH back to the user's wallet
        GemLike(gem.stETH()).transfer(msg.sender, unwrapped);
    }

    function wipeAllAndFreeStETH(
        address WstETHJoin,
        address daiJoin,
        uint256 cdp,
        uint256 amtC
    ) public {
        address urn = manager.urns(cdp);
        bytes32 ilk = manager.ilks(cdp);
        (, uint256 art) = vat.urns(ilk, urn);
        GemLike gem = GemJoinLike(WstETHJoin).gem();

        // Joins DAI amount into the vat
        daiJoin_join(daiJoin, urn, _getWipeAllWad(urn, urn, ilk));
        // Calculates how much WstETH to exit
        uint256 wadC = gem.getWstETHByStETH(amtC);
        // Paybacks debt to the CDP and unlocks WstETH amount from it
        _frob(
            cdp,
            -_toInt256(wadC),
            -_toInt256(art)
        );
        // Moves the amount from the CDP urn to proxy's address
        _flux(cdp, address(this), wadC);
        // Exits WstETH amount to proxy address as a token
        GemJoinLike(WstETHJoin).exit(address(this), wadC);
        // Converts WstETH to StETH
        uint256 unwrapped = gem.unwrap(wadC);
        // Sends StETH back to the user's wallet
        GemLike(gem.stETH()).transfer(msg.sender, unwrapped);
    }
}

contract DssProxyActionsEndStETH is Common {

    constructor(address vat_, address manager_) public Common(vat_, manager_) {}

    // Internal functions

    function _free(
        address end,
        uint256 cdp
    ) internal returns (uint256 ink) {
        bytes32 ilk = manager.ilks(cdp);
        address urn = manager.urns(cdp);
        uint256 art;
        (ink, art) = vat.urns(ilk, urn);

        // If CDP still has debt, it needs to be paid
        if (art > 0) {
            EndLike(end).skim(ilk, urn);
            (ink,) = vat.urns(ilk, urn);
        }
        // Approves the manager to transfer the position to proxy's address in the vat
        if (vat.can(address(this), address(manager)) == 0) {
            vat.hope(address(manager));
        }
        // Transfers position from CDP to the proxy address
        manager.quit(cdp, address(this));
        // Frees the position and recovers the collateral in the vat registry
        EndLike(end).free(ilk);
    }

    function freeStETH(
        address WstETHJoin,
        address end,
        uint256 cdp
    ) public {
        GemLike gem = GemJoinLike(WstETHJoin).gem();
        uint256 wad = _free(end, cdp);
        // Exits WstETH amount to proxy address as a token
        GemJoinLike(WstETHJoin).exit(address(this), wad);
        // Converts WstETH to StETH
        uint256 unwrapped = gem.unwrap(wad);
        // Sends StETH back to the user's wallet
        GemLike(gem.stETH()).transfer(msg.sender, unwrapped);
    }

    function cashStETH(
        address WstETHJoin,
        address end,
        bytes32 ilk,
        uint256 wad
    ) public {
        GemLike gem = GemJoinLike(WstETHJoin).gem();
        EndLike(end).cash(ilk, wad);
        uint256 wadC = _mul(wad, EndLike(end).fix(ilk)) / RAY;
        // Exits WstETH amount to proxy address as a token
        GemJoinLike(WstETHJoin).exit(address(this), wadC);
        // Converts WstETH to StETH
        uint256 unwrapped = gem.unwrap(wadC);
        // Sends StETH back to the user's wallet
        GemLike(gem.stETH()).transfer(msg.sender, unwrapped);
    }
}