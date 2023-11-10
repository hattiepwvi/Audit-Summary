// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "./IOrder.sol";
import "./IEvent.sol";

// @title IOrderCallbackReceiver
// @dev interface for an order callback contract
interface IOrderCallbackReceiver {
  // @dev called after an order execution
  // @param key the key of the order
  // @param order the order that was executed
  function afterOrderExecution(
    bytes32 key,
    IOrder.Props memory order,
    IEvent.Props memory eventData
  ) external;

  // @dev called after an order cancellation
  // @param key the key of the order
  // @param order the order that was cancelled
  function afterOrderCancellation(
    bytes32 key,
    IOrder.Props memory order,
    IEvent.Props memory eventData
  ) external;

  // @dev called after an order has been frozen, see OrderUtils.freezeOrder in OrderHandler for more info
  // @param key the key of the order
  // @param order the order that was frozen
  function afterOrderFrozen(
    bytes32 key,
    IOrder.Props memory order,
    IEvent.Props memory eventData
  ) external;
}
