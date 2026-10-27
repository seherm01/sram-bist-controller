# SRAM Built-In Self-Test (BIST)



# Overview

This SystemVerilog module implements a Built-In Self-Test (BIST) controller for testing SRAM functionality.

The controller writes test patterns to even and odd memory addresses, reads the stored values back, and flags any mismatches between the expected and returned data.

# Features

Finite state machine (FSM) for controlling the BIST sequence.

Tests even and odd SRAM addresses across the 18-bit address space.

Uses XOR-based data patterns (16'hA5A5 and 16'h5A5A).

Supports active-low SRAM write enable.

Detects data mismatches during readback.

Provides completion and mismatch status outputs.
