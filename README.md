# hello_me


Exercise 1 - UI Refactoring
Dry part - Answers:
1)SnappingSheetController class is used to implement the controller pattern in this library.
some features it allows:
*snapToPosition - Snaps to a given snapping position.
*stopCurrentSnapping - Stops the current snapping if there is one ongoing.
*currentlySnapping - Returns true if the snapping sheet is currently trying to snap to a position.
*isAttached - If a state is attached to this controller. isAttached must be true before any function call from this controller is made.

2)as mentioned before, snapToPosition allows the bottom sheet to snap into position, and the parameter that 
controls this behavior is SnappingPosition(first and only parameter), which is a class that defines the animation, including its factoring,
curve and duration.

3)
Advantage of InkWell over GestureDetector:
InkWell supports different kinds of ripple effects which makes tapping more UX friendly, while GestureDetector
doesn't support ripple effects at all.

Advantage of GestureDetector over InkWell:
GestureDetector supports detection and handling of more complex kind of clicks - like dragging, pinching, double clicks,
long clicks, zooming in and more... while InkWell support a limited amount of different click types.



